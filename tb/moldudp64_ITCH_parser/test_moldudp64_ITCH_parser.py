import random, struct
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly, ClockCycles, with_timeout
from cocotbext.axi import AxiStreamBus, AxiStreamSource, AxiStreamFrame
from scapy.all import Ether, IP, UDP, Raw

PORT = 0x5678
random.seed(12345)

def pauses(p):
    while True:
        yield random.random() < p

# message builders
def timestamp():
    return random.getrandbits(48).to_bytes(6, "big")

def add_order(loc, ref, side, shares, stock, price):      # 36 bytes
    return struct.pack(">cHH6sQcI8sI", b"A", loc, 0, timestamp(), ref, side,
                       shares, stock.ljust(8).encode(), price)

def executed(loc, ref, shares):                           # 31 bytes
    return struct.pack(">cHH6sQIQ", b"E", loc, 0, timestamp(), ref, shares,
                       random.getrandbits(64))

def cancel(loc, ref, shares):                             # 23 bytes
    return struct.pack(">cHH6sQI", b"X", loc, 0, timestamp(), ref, shares)

def delete(loc, ref):                                     # 19 bytes
    return struct.pack(">cHH6sQ", b"D", loc, 0, timestamp(), ref)

def system_event(loc):                                    # 12 bytes
    return struct.pack(">cHH6sc", b"S", loc, 0, timestamp(), b"O")


#creating a message with random type and random values for the fields
def random_msg():
    k = random.choice("AEXDS")
    loc, ref = random.getrandbits(16), random.getrandbits(64)
    if k == "A": return add_order(loc, ref, random.choice([b"B", b"S"]),
                                  random.getrandbits(32), "AAPL", random.getrandbits(32))
    if k == "E": return executed(loc, ref, random.getrandbits(32))
    if k == "X": return cancel(loc, ref, random.getrandbits(32))
    if k == "D": return delete(loc, ref)
    return system_event(loc)

# creating moldudp64 payload with a session, sequence number, message count, and the messages themselves
def mold_payload(msgs, session=b"SESSION001"):
    body = b"".join(struct.pack(">H", len(m)) + m for m in msgs)
    return session + struct.pack(">QH", random.getrandbits(48), len(msgs)) + body

# wrap the payload in an Ethernet/IP/UDP frame with a given destination port
def wrap(payload, dport):
    f = (Ether(src="aa:bb:cc:dd:ee:ff", dst="11:22:33:44:55:66")
         / IP(src="10.0.0.1", dst="239.1.2.3", proto=17)
         / UDP(sport=1234, dport=dport, chksum=0) / Raw(payload))
    return bytes(f)

def make_frame(kind="good", n_msgs=None):
    """Returns (frame_bytes, is_good). Every fault leaves the rest valid."""
    n = random.randint(0, 8) if n_msgs is None else n_msgs
    payload = mold_payload([random_msg() for _ in range(n)])
    f = bytearray(wrap(payload, PORT + 1 if kind == "dport" else PORT))
    if kind == "badsum":
        f[24] ^= 0x01                      # corrupt the IP header checksum
    return bytes(f), kind == "good"


def decode(m):
    t, n = chr(m[0]), len(m)
    loc, ref = int.from_bytes(m[1:3], "big"), int.from_bytes(m[11:19], "big")
    if t == "A" and n == 36:
        return (t, loc, ref, int(m[19:20] == b"B"),
                int.from_bytes(m[20:24], "big"), int.from_bytes(m[32:36], "big"))
    if t == "E" and n == 31:
        return (t, loc, ref, 0, int.from_bytes(m[19:23], "big"), 0)
    if t == "X" and n == 23:
        return (t, loc, ref, 0, int.from_bytes(m[19:23], "big"), 0)
    return None                               # D and S: parser forwards them, decoder ignores them

# model: considering the frame bytes
def model_hdr(frame):
    p = frame[42:]                         # payload starts at byte 42
    return (int.from_bytes(p[0:10], "big"),     # session
            int.from_bytes(p[10:18], "big"),    # sequence number
            int.from_bytes(p[18:20], "big"))    # message count

def model_msgs(frame):
    p = frame[42:]
    msgs, off = [], 20
    for _ in range(int.from_bytes(p[18:20], "big")):
        n = int.from_bytes(p[off:off+2], "big")
        msgs.append(p[off+2:off+2+n])
        off += 2 + n
    return msgs

# DUT monitor
async def pipeline_monitor(dut, records):
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.reset.value) == 1:
            continue
        if int(dut.valid_header.value):
            records.append({"hdr": (int(dut.session.value),
                                    int(dut.sequence_no.value),
                                    int(dut.message_count.value)),
                            "msgs": [], "dec": []})
        if int(dut.valid_message.value):
            assert records, "valid_message before any header"
            n = int(dut.message_length.value)
            data = int(dut.message_data.value) & ((1 << (8 * n)) - 1)
            records[-1]["msgs"].append(data.to_bytes(n, "little"))     # raw bytes, byte 0 first

            if int(dut.known_and_correct_length.value):                # decoder output
                t   = chr(int(dut.message_type.value))
                loc = int(dut.stock_locate.value)
                ref = int(dut.order_reference_number.value)
                if t == "A":
                    d = (t, loc, ref, int(int(dut.buy_sell_indicator.value) == ord("B")),
                         int(dut.shares.value), int(dut.price.value))
                elif t == "E":
                    d = (t, loc, ref, 0, int(dut.executed_shares.value), 0)
                else:
                    d = (t, loc, ref, 0, int(dut.cancelled_shares.value), 0)
                records[-1]["dec"].append(d)

# runner: send frames to the DUT and check the results
async def run_frames(dut, items, p_src=0.0):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    src = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.reset)
    src.set_pause_generator(pauses(p_src))

    dut.reset.value = 1
    await ClockCycles(dut.clk, 5)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

    records = []
    cocotb.start_soon(pipeline_monitor(dut, records))

    for f, _ in items:
        await src.send(AxiStreamFrame(f))
    await with_timeout(src.wait(), 500, "us")
    await ClockCycles(dut.clk, 30)

    assert len(records) == len(items), f"expected {len(items)} headers, saw {len(records)}"
    for i, ((f, good), rec) in enumerate(zip(items, records)):
        assert rec["hdr"] == model_hdr(f), f"frame {i}: header mismatch"
        exp_raw = model_msgs(f) if good else []
        exp_dec = [d for d in map(decode, exp_raw) if d]
        assert rec["msgs"] == exp_raw, (f"frame {i}: raw messages differ "
                                        f"(got {len(rec['msgs'])}, expected {len(exp_raw)})")
        assert rec["dec"] == exp_dec, f"frame {i}: decoded fields differ\n got {rec['dec']}\n exp {exp_dec}"



#tests
@cocotb.test()
async def heartbeat_and_small(dut):
    await run_frames(dut, [make_frame("good", n) for n in (0, 1, 2, 0, 3)])

@cocotb.test()
async def random_good_no_stalls(dut):
    await run_frames(dut, [make_frame("good") for _ in range(100)])

@cocotb.test()
async def bad_frames_between_good(dut):
    kinds = ["good", "dport", "good", "badsum", "good", "good", "dport", "good"]
    await run_frames(dut, [make_frame(k) for k in kinds] * 10)

@cocotb.test()
async def random_with_source_stalls(dut):
    kinds = ["good", "good", "good", "dport", "badsum"]
    await run_frames(dut, [make_frame(random.choice(kinds)) for _ in range(150)], p_src=0.4)