import random, cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, ClockCycles, with_timeout
from cocotbext.axi import AxiStreamBus, AxiStreamSource, AxiStreamSink, AxiStreamFrame
from scapy.all import Ether, IP, UDP, Raw

PORT = 0x5678          # must match the wrapper's PORT parameter

def pauses(p):
    while True:
        yield random.random() < p

# ---------- frame generation ----------
def ip_checksum(hdr):
    s = sum(int.from_bytes(hdr[i:i+2], "big") for i in range(0, len(hdr), 2))
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF

def fix_ip_checksum(b):
    b[24:26] = b"\x00\x00"
    b[24:26] = ip_checksum(bytes(b[14:34])).to_bytes(2, "big")

def build(kind="good", payload_len=20):
    payload = bytes(random.randrange(256) for _ in range(payload_len))
    f = (Ether(src="aa:bb:cc:dd:ee:ff", dst="11:22:33:44:55:66")
         / IP(src="10.0.0.1", dst="239.1.2.3", proto=17, id=random.randrange(65536))
         / UDP(sport=1234, dport=PORT, chksum=0) / Raw(payload))
    b = bytearray(bytes(f))
    if   kind == "ethertype": b[12:14] = b"\x86\xdd"
    elif kind == "proto":     b[23] = 6
    elif kind == "dport":     b[36:38] = ((PORT + 1) & 0xFFFF).to_bytes(2, "big")
    elif kind == "udplen":    b[38:40] = (int.from_bytes(b[38:40], "big") + 1).to_bytes(2, "big")
    fix_ip_checksum(b)                      # every fault except badsum keeps a valid IP checksum
    if kind == "badsum":
        b[24] ^= 0x01
    return bytes(b)                          # no padding: payload >= 20 gives frame >= 62 bytes

# ---------- independent model (plain byte slicing) ----------
def model_ok(f):
    s = sum(int.from_bytes(f[i:i+2], "big") for i in range(14, 34, 2))
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    total_len = int.from_bytes(f[16:18], "big")
    frag      = int.from_bytes(f[20:22], "big")
    udp_len   = int.from_bytes(f[38:40], "big")
    dport     = int.from_bytes(f[36:38], "big")
    return (f[12:14] == b"\x08\x00" and f[14] == 0x45 and (frag & 0x3FFF) == 0
            and f[23] == 17 and s == 0xFFFF
            and dport == PORT and udp_len == total_len - 20)

def last_tuser(frame):
    t = frame.tuser
    return int(t[-1]) if isinstance(t, (list, tuple)) else int(t)

# ---------- output handshake monitor ----------
async def out_monitor(dut):
    """valid && !ready => next cycle valid still 1 and data/keep/last unchanged."""
    prev = None
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.reset.value) == 1:
            prev = None
            continue
        v, r = int(dut.m_axis_tvalid.value), int(dut.m_axis_tready.value)
        if prev is not None:
            assert v, "m_axis_tvalid dropped during a stall"
            cur = (int(dut.m_axis_tdata.value), int(dut.m_axis_tkeep.value),
                   int(dut.m_axis_tlast.value))
            assert cur == prev, "output beat changed during a stall"
        prev = None
        if v and not r:
            prev = (int(dut.m_axis_tdata.value), int(dut.m_axis_tkeep.value),
                    int(dut.m_axis_tlast.value))

# ---------- runner ----------
async def run_frames(dut, frames, p_src=0.0, p_sink=0.0):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    src  = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.reset)
    sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.reset)
    src.set_pause_generator(pauses(p_src))
    sink.set_pause_generator(pauses(p_sink))

    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await RisingEdge(dut.clk)
    cocotb.start_soon(out_monitor(dut))

    for f in frames:
        await src.send(AxiStreamFrame(f))

    for i, f in enumerate(frames):
        got = await with_timeout(sink.recv(), 500, "us")
        exp_payload = f[42:]
        assert bytes(got.tdata) == exp_payload, (
            f"frame {i} (len {len(f)}): payload mismatch\n"
            f" got {bytes(got.tdata).hex()}\n exp {exp_payload.hex()}")
        exp_tuser = 0 if model_ok(f) else 1
        assert last_tuser(got) == exp_tuser, (
            f"frame {i}: tuser={last_tuser(got)}, expected {exp_tuser}")

    await ClockCycles(dut.clk, 10)
    assert sink.empty(), "extra output frames appeared"

# ---------- tests ----------
KINDS = ["good", "ethertype", "proto", "dport", "udplen", "badsum"]

@cocotb.test()
async def payload_length_sweep(dut):
    # payload 20..45 bytes covers every last-beat size (k = 1..8) and the flush/no-flush split
    frames = [build("good", n) for n in range(20, 46)]
    await run_frames(dut, frames)

@cocotb.test()
async def each_fault_between_good(dut):
    frames = []
    for k in KINDS[1:]:
        frames += [build("good", random.randint(20, 60)), build(k, random.randint(20, 60))]
    frames.append(build("good"))
    await run_frames(dut, frames)

@cocotb.test()
async def minimum_payload_back_to_back(dut):
    # 20-byte payload is the tightest verdict timing; no idle cycles between frames
    frames = [build(random.choice(KINDS), 20) for _ in range(60)]
    await run_frames(dut, frames)

@cocotb.test()
async def long_frames(dut):
    frames = [build("good", n) for n in (100, 255, 256, 1000)]
    await run_frames(dut, frames)

@cocotb.test()
async def random_mix_no_stalls(dut):
    frames = [build(random.choice(KINDS), random.randint(20, 200)) for _ in range(150)]
    await run_frames(dut, frames)

@cocotb.test()
async def random_mix_with_stalls(dut):
    frames = [build(random.choice(KINDS), random.randint(20, 200)) for _ in range(200)]
    await run_frames(dut, frames, p_src=0.4, p_sink=0.4)

@cocotb.test()
async def sink_stalls_flush(dut):
    # heavy sink stalls exercise the flush_pending / s_axis_tready path
    frames = [build("good", random.randint(20, 45)) for _ in range(100)]
    await run_frames(dut, frames, p_sink=0.7)
    
@cocotb.test()
async def source_stalls_flush(dut):
    frames = [build("good", 25) for _ in range(200)]
    await run_frames(dut, frames, p_src=0.7)

@cocotb.test()
async def source_and_sink_stalls_flush(dut):
    frames = [build("good", 25) for _ in range(200)]
    await run_frames(dut, frames, p_src=0.7, p_sink=0.7)
