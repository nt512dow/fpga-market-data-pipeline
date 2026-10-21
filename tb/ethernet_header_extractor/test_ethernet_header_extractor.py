import random, cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, ReadOnly
from cocotbext.axi import AxiStreamBus, AxiStreamSource, AxiStreamSink, AxiStreamFrame
import os

def pauses(p):
    while True:
        yield random.random() < p #randomly pause the cycle, simulating backpressure

def rand_frame(length):
    return bytes(random.randrange(256) for _ in range(length))

def has_full_header(f):
    return len(f) >= 14          # contract: header complete only if 14+ bytes arrived

async def header_monitor(dut, captured):
    prev_valid, prev_fields = 0, None
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.reset.value) == 1:
            prev_valid, prev_fields = 0, None
            continue
        v = int(dut.valid_header.value)
        fields = (int(dut.destination_MAC.value),
                  int(dut.source_MAC.value),
                  int(dut.ether_type.value))
        if v and not prev_valid:                 # rising edge = one header found
            captured.append(fields)
        if v and prev_valid:                     # hold check
            assert fields == prev_fields, "fields changed while valid_header was high"
        prev_valid, prev_fields = v, fields

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
    cocotb.start_soon(header_monitor(dut, captured))

    for f in frames:
        await src.send(AxiStreamFrame(f))
    for i, f in enumerate(frames):
        got = await sink.recv()
        assert bytes(got.tdata) == f, f"frame {i}: stream corrupted"

    await ClockCycles(dut.clk, 5)

    expected = [(int.from_bytes(f[0:6], "big"),
                 int.from_bytes(f[6:12], "big"),
                 int.from_bytes(f[12:14], "big"))
                for f in frames if has_full_header(f)]
    assert len(captured) == len(expected), \
        f"expected {len(expected)} headers, saw {len(captured)}"
    for i, (got, exp) in enumerate(zip(captured, expected)):
        assert got == exp, f"header {i}: got {[hex(x) for x in got]}, expected {[hex(x) for x in exp]}"

# ---- directed tests ----

@cocotb.test()
async def boundary_lengths(dut):
    # 14 = exactly the header; 15,16 straddle the beat boundary; 60 = real minimum frame
    frames = [rand_frame(n) for n in (14, 15, 16, 17, 60, 64, 65)]
    await run_frames(dut, frames)

@cocotb.test()
async def truncated_headers_do_not_fire(dut):
    # 9..13 bytes: two beats, but the header is incomplete -> valid_header must not rise
    frames = [rand_frame(n) for n in (9, 10, 11, 12, 13)]
    await run_frames(dut, frames)       # expected list is empty, so captured must be empty

@cocotb.test()
async def good_bad_good(dut):
    # a short frame between two good ones: it must not fire, and the next frame must recover
    frames = [rand_frame(60), rand_frame(10), rand_frame(60),
              rand_frame(13), rand_frame(14), rand_frame(100)]
    await run_frames(dut, frames)

@cocotb.test()
async def back_to_back_many_lengths(dut):
    frames = [rand_frame(random.randint(9, 130)) for _ in range(100)]
    await run_frames(dut, frames)

#random backpressure
@cocotb.test()
async def random_stalls(dut):
    frames = [rand_frame(random.randint(9, 130)) for _ in range(200)]
    await run_frames(dut, frames, p_src=0.4, p_sink=0.4)

@cocotb.test()
async def sink_stalls_only(dut):
    frames = [rand_frame(random.randint(9, 130)) for _ in range(100)]
    await run_frames(dut, frames, p_sink=0.6)
