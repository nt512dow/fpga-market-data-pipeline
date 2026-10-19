#!/usr/bin/env bash
# Activates OSS CAD Suite inside this script's own process only.
source ~/tools/oss-cad-suite/environment

set -e
cd "$(dirname "$0")"
mkdir -p build

for outreg in 0 1; do
  for lp in 0 1; do
    tag=outreg${outreg}_lp${lp}
    echo "=== $tag ==="

    yosys -q -l build/$tag.yosys.log -p "
      read_verilog -sv ../rtl/skid_buffer.v
      chparam -set DATA_WIDTH 64 -set OPT_OUTREG $outreg -set OPT_LOWPOWER $lp skid_buffer
      synth_ecp5 -top skid_buffer -json build/$tag.json
      tee -o build/$tag.stat stat
    "

    nextpnr-ecp5 --85k --package CABGA381 --json build/$tag.json \
      --freq 300 --out-of-context -l build/$tag.nextpnr.log || true

    grep -E "TRELLIS_FF|LUT4" build/$tag.stat || true
    grep -i "max frequency" build/$tag.nextpnr.log | tail -1 || true
  done
done