import random, cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly
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
        if dut.rst.value == 1:
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

async def run(dut, p_src, p_sink, n=200):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    src  = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst)
    sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst)
    src.set_pause_generator(pauses(p_src))
    sink.set_pause_generator(pauses(p_sink))

    dut.rst.value = 1
    for _ in range(5): await RisingEdge(dut.clk)
    dut.rst.value = 0
    cocotb.start_soon(handshake_monitor(dut))

    sent = [bytes(random.randrange(256) for _ in range(random.randint(1, 100)))
            for _ in range(n)]
    for f in sent:
        await src.send(AxiStreamFrame(f))
    for i, f in enumerate(sent):
        got = await sink.recv()
        assert bytes(got.tdata) == f, f"frame {i} mismatch"

@cocotb.test()
async def no_pauses(dut):      await run(dut, 0.0, 0.0)
@cocotb.test()
async def sink_stalls(dut):    await run(dut, 0.0, 0.6)
@cocotb.test()
async def src_stalls(dut):     await run(dut, 0.6, 0.0)
@cocotb.test()
async def both_random(dut):   await run(dut, 0.4, 0.4)