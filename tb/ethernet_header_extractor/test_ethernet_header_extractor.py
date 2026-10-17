import random, cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, ReadOnly
from cocotbext.axi import AxiStreamBus, AxiStreamSource, AxiStreamSink, AxiStreamFrame
import os

def pauses(p):
    while True:
        yield random.random() < p #randomly pause the cycle, simulating backpressure

async def handshake_monitor(dut):
    """valid && !ready in one cycle => next cycle valid still 1 and data unchanged."""
    prev = None
    LOWPOWER = os.environ.get("OPT_LOWPOWER", "0") == "1"
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if dut.reset.value == 1:
            prev = None
            continue
        v, r = int(dut.m_axis_tvalid.value), int(dut.m_axis_tready.value)
        d = int(dut.m_axis_tdata.value)
        if LOWPOWER and dut.skid_buffer_unit.o_valid.value == 0:
            assert int(dut.skid_buffer_unit.o_data.value) == 0
        
        if prev is not None:
            assert v, "m_axis_tvalid dropped during a stall"
            assert d == prev, "m_axis_tdata changed during a stall"
        prev = d if (v and not r) else None
        
async def header_monitor(dut, captured):
    prev = 0
    while True:
        await RisingEdge(dut.clk)
        await ReadOnly()
        if int(dut.reset.value) == 1:
            prev = 0
            continue
        v = int(dut.valid_header.value)
        if v and not prev:                      # rising edge of valid_header
            captured.append((int(dut.destination_MAC.value),
                             int(dut.source_MAC.value),
                             int(dut.ether_type.value)))
        prev = v
        
async def run(dut, p_src, p_sink, n=200):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    src  = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.reset)
    sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.reset)
    src.set_pause_generator(pauses(p_src))
    sink.set_pause_generator(pauses(p_sink))

    dut.reset.value = 1
    for _ in range(5): await RisingEdge(dut.clk)
    dut.reset.value = 0
    captured = []
    cocotb.start_soon(handshake_monitor(dut))
    cocotb.start_soon(header_monitor(dut, captured))

    sent = [bytes(random.randrange(256) for _ in range(random.randint(60, 120)))
            for _ in range(n)]
    for f in sent:
        await src.send(AxiStreamFrame(f)) #queue everything
    for i, f in enumerate(sent):
        got = await sink.recv()
        assert bytes(got.tdata) == f, f"frame {i} mismatch"

    # await ClockCycles(dut.clk, 5)
    assert len(captured) == n, f"expected {n} header captures, got {len(captured)}"
    for i, (f, (dst, src_mac, et)) in enumerate(zip(sent, captured)):
        assert dst == int.from_bytes(f[0:6], "big"), f"frame {i} dst_mac mismatch"
        assert src_mac == int.from_bytes(f[6:12], "big"), f"frame {i} src_mac mismatch"
        assert et == int.from_bytes(f[12:14], "big"), f"frame {i} ethertype mismatch"

@cocotb.test()
async def no_pauses(dut):      await run(dut, 0.0, 0.0)
@cocotb.test()
async def sink_stalls(dut):    await run(dut, 0.0, 0.6)
@cocotb.test()
async def src_stalls(dut):     await run(dut, 0.6, 0.0)
@cocotb.test()
async def both_random(dut):   await run(dut, 0.4, 0.4)