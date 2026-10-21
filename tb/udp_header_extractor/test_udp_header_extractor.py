import random, cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, ClockCycles, with_timeout
from cocotbext.axi import AxiStreamBus, AxiStreamSource, AxiStreamSink, AxiStreamFrame
from scapy.all import Ether, IP, UDP, Raw

PORT = 0x5678  # Default from parameter

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

def build(kind="good", payload_len=18, src="10.0.0.1", dst="239.1.2.3"):
    payload = bytes(random.randrange(256) for _ in range(payload_len))
    f = (Ether(src="aa:bb:cc:dd:ee:ff", dst="11:22:33:44:55:66")
         / IP(src=src, dst=dst, proto=17, id=random.randrange(65536),
              ttl=random.randrange(1, 256))
         / UDP(sport=1234, dport=PORT) / Raw(payload))
    b = bytearray(bytes(f))
    
    # IP faults
    if   kind == "ethertype": b[12:14] = b"\x86\xdd"
    elif kind == "proto":     b[23] = 6
    elif kind == "version":   b[14] = (0x55 & 0xF0) | (b[14] & 0x0F)
    elif kind == "ihl":       b[14] = (b[14] & 0xF0) | 0x06
    elif kind == "mf":        b[20] |= 0x20
    elif kind == "offset":    b[21] = 100
    
    # UDP faults
    elif kind == "bad_dport": b[36:38] = b"\x11\x11"
    elif kind == "bad_len":   b[38:40] = b"\x00\x00"
    
    fix_ip_checksum(b)
    if kind == "badsum":
        b[24] ^= 0x01
        
    return bytes(b.ljust(60, b"\x00"))

# ---------- independent reference model ----------
def model(f):
    # IP checks
    ip_sum = sum(int.from_bytes(f[14:34][i:i+2], "big") for i in range(0, 20, 2))
    while ip_sum >> 16:
        ip_sum = (ip_sum & 0xFFFF) + (ip_sum >> 16)
    frag = int.from_bytes(f[20:22], "big")
    ip_total_len = int.from_bytes(f[16:18], "big")
    
    ok_ip = (f[12:14] == b"\x08\x00" and (f[14] >> 4) == 4 and (f[14] & 0xF) == 5
             and (frag & 0x3FFF) == 0 and f[23] == 17 and ip_sum == 0xFFFF)
             
    # UDP checks
    dst_port = int.from_bytes(f[36:38], "big")
    udp_length = int.from_bytes(f[38:40], "big")
    
    # Assuming `ip_udp_payload_length` in DUT is total IP length 
    ok_udp = ok_ip and (dst_port == PORT) and (udp_length == ip_total_len - 20)

    return dict(
        ok_ip=int(ok_ip),
        ok_udp=int(ok_udp),
        src_port=int.from_bytes(f[34:36], "big"),
        dst_port=dst_port,
        udp_length=udp_length,
        udp_checksum=int.from_bytes(f[40:42], "big")
    )

# ---------- monitor ----------
async def udp_monitor(dut, captured):
    prev_valid, prev = 0, None
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.reset.value) == 1:
            prev_valid, prev = 0, None
            continue
            
        v = int(dut.valid_udp.value)
        fields = dict(
            ok_ip=int(dut.ok_ip.value),
            ok_udp=int(dut.ok_udp.value),
            src_port=int(dut.source_port.value),
            dst_port=int(dut.destination_port.value),
            udp_length=int(dut.udp_length.value),
            udp_checksum=int(dut.udp_checksum.value)
        )
        
        if v and not prev_valid:
            captured.append(fields)
        if v and prev_valid:
            assert fields == prev, "UDP fields/ok_udp changed while valid_udp was high"
            
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
    cocotb.start_soon(udp_monitor(dut, captured))

    for f in frames:
        await src.send(AxiStreamFrame(f))
    for i, f in enumerate(frames):
        got = await with_timeout(sink.recv(), 500, "us")
        assert bytes(got.tdata) == f, f"frame {i}: stream corrupted"
    await ClockCycles(dut.clk, 8)

    assert len(captured) == len(frames), f"expected {len(frames)} verdicts, got {len(captured)}"
    for i, (f, got) in enumerate(zip(frames, captured)):
        assert got == model(f), f"frame {i}: got {got}, expected {model(f)}"

# ---------- tests ----------
KINDS = ["good", "ethertype", "proto", "version", "ihl", "mf", "offset", "badsum", "bad_dport", "bad_len"]

@cocotb.test()
async def each_fault_between_good_frames(dut):
    frames = []
    for k in KINDS[1:]:
        frames += [build("good"), build(k)]
    frames.append(build("good"))
    await run_frames(dut, frames)

@cocotb.test()
async def lengths(dut):
    # payload_len covers the padding behavior as well as larger frames
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