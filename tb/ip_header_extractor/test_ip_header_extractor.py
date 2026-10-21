import random, cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, ClockCycles, with_timeout
from cocotbext.axi import AxiStreamBus, AxiStreamSource, AxiStreamSink, AxiStreamFrame
from scapy.all import Ether, IP, UDP, Raw

def pauses(p):
    while True:
        yield random.random() < p

# ---------- frame generation ----------
def ip_checksum(hdr):
    s = sum(int.from_bytes(hdr[i:i+2], "big") for i in range(0, len(hdr), 2))
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF

def fix_checksum(b):
    b[24:26] = b"\x00\x00"
    b[24:26] = ip_checksum(bytes(b[14:34])).to_bytes(2, "big")

def build(kind="good", payload_len=18, src="10.0.0.1", dst="239.1.2.3"):
    payload = bytes(random.randrange(256) for _ in range(payload_len))
    f = (Ether(src="aa:bb:cc:dd:ee:ff", dst="11:22:33:44:55:66")
         / IP(src=src, dst=dst, proto=17, id=random.randrange(65536),
              ttl=random.randrange(1, 256))
         / UDP(sport=1234, dport=5678) / Raw(payload))
    b = bytearray(bytes(f))
    if   kind == "ethertype": b[12:14] = b"\x86\xdd"
    elif kind == "proto":     b[23] = 6
    elif kind == "version":   b[14] = 0x55
    elif kind == "ihl":       b[14] = 0x46
    elif kind == "mf":        b[20] |= 0x20          # More Fragments flag
    elif kind == "offset":    b[21] = 100            # fragment offset
    fix_checksum(b)                                   # every fault except badsum keeps a valid checksum
    if kind == "badsum":
        b[24] ^= 0x01
    return bytes(b.ljust(60, b"\x00"))

# ---------- independent reference model (plain byte slicing) ----------
def model(f):
    s = sum(int.from_bytes(f[i:i+2], "big") for i in range(14, 34, 2))
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    frag = int.from_bytes(f[20:22], "big")
    ok = (f[12:14] == b"\x08\x00" and (f[14] >> 4) == 4 and (f[14] & 0xF) == 5
          and (frag & 0x3FFF) == 0 and f[23] == 17 and s == 0xFFFF)
    return dict(ok=int(ok), proto=f[23],
                src=int.from_bytes(f[26:30], "big"),
                dst=int.from_bytes(f[30:34], "big"),
                total_len=int.from_bytes(f[16:18], "big"))

# ---------- monitor ----------
async def ip_monitor(dut, captured):
    prev_valid, prev = 0, None
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.reset.value) == 1:
            prev_valid, prev = 0, None
            continue
        v = int(dut.valid_ip.value)
        fields = dict(ok=int(dut.ok_ip.value),
                      proto=int(dut.protocol.value),
                      src=int(dut.source_ip_address.value),
                      dst=int(dut.destination_ip_address.value),
                      total_len=int(dut.total_length.value))
        if v and not prev_valid:
            captured.append(fields)
        if v and prev_valid:
            assert fields == prev, "IP fields/ok_ip changed while valid_ip was high"
        prev_valid, prev = v, fields

# ---------- common runner ----------
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

    captured = []
    cocotb.start_soon(ip_monitor(dut, captured))

    for f in frames:
        await src.send(AxiStreamFrame(f))
    for i, f in enumerate(frames):
        got = await with_timeout(sink.recv(), 500, "us")
        assert bytes(got.tdata) == f, f"frame {i}: stream corrupted"
    await ClockCycles(dut.clk, 8)

    assert len(captured) == len(frames), f"expected {len(frames)} verdicts, got {len(captured)}"
    for i, (f, got) in enumerate(zip(frames, captured)):
        assert got == model(f), f"frame {i}: got {got}, expected {model(f)}" #manual check using a model function that we coded, not relying on dut

# ---------- tests ----------
KINDS = ["good", "ethertype", "proto", "version", "ihl", "mf", "offset", "badsum"]

@cocotb.test()
async def each_fault_between_good_frames(dut):
    frames = []
    for k in KINDS[1:]:
        frames += [build("good"), build(k)]
    frames.append(build("good"))
    await run_frames(dut, frames)

@cocotb.test()
async def checksum_carry_stress(dut):
    frames = [build("good", src="255.255.255.255", dst="255.255.255.255"),
              build("good", src="255.255.0.255", dst="0.255.255.255")]
    frames += [build("good", src=".".join(str(random.randrange(256)) for _ in range(4)),
                     dst=".".join(str(random.randrange(256)) for _ in range(4)))
               for _ in range(50)]
    await run_frames(dut, frames)

@cocotb.test()
async def lengths(dut):
    frames = [build("good", payload_len=n) for n in (18, 19, 22, 23, 100, 958)]
    await run_frames(dut, frames)

@cocotb.test()
async def random_mix_no_stalls(dut):
    frames = [build(random.choice(KINDS), random.randint(18, 200)) for _ in range(150)]
    await run_frames(dut, frames)

@cocotb.test()
async def random_mix_with_stalls(dut):
    frames = [build(random.choice(KINDS), random.randint(18, 200)) for _ in range(200)]
    await run_frames(dut, frames, p_src=0.4, p_sink=0.4)