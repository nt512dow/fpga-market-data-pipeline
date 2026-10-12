# This file is public domain, it can be freely copied without restrictions.
# SPDX-License-Identifier: CC0-1.0

# Makefile

# The simulator we want to run our tests with.
SIM ?= icarus

# The top-level language of the design (verilog or vhdl).
TOPLEVEL_LANG = verilog

# List of Verilog source files.
VERILOG_SOURCES = $(CURDIR)/../../rtl/skid_buffer.v $(CURDIR)/skid_wrapper.v

# The name of the toplevel module/entity in your design.
COCOTB_TOPLEVEL = skid_wrapper

# The Python modules which contain your testcases.
# The current directory is included in the Python path,
# so you can just specify the module name without the .py extension.
COCOTB_TEST_MODULES = test_skid

# Enable waveform generation.
WAVES = 1

#Setting parameters, run it with make OPT_LOWPOWER=1 OPT_OUTREG=1 to enable lowpower and outreg options, run make clean between configs 
OPT_LOWPOWER ?= 0
OPT_OUTREG ?= 0
export OPT_LOWPOWER OPT_OUTREG
COMPILE_ARGS += -Pskid_wrapper.OPT_LOWPOWER=$(OPT_LOWPOWER) -Pskid_wrapper.OPT_OUTREG=$(OPT_OUTREG)
# Includes cocotb's Makefiles which define the build and simulation flows for each supported simulator.
# This must be included *after* all of the variables above are defined.
include $(shell cocotb-config --makefiles)/Makefile.sim
