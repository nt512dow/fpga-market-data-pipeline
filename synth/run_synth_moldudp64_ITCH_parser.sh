#!/usr/bin/env bash
# Activates OSS CAD Suite inside this script's own process only.
source ~/tools/oss-cad-suite/environment

set -e
cd "$(dirname "$0")"
mkdir -p build


tag=moldudp64_ITCH_parser_wrapper
echo "=== $tag ==="

yosys -q -l build/$tag.yosys.log -p "
  read_verilog -sv ../rtl/ethernet_header_extractor.v  ../rtl/ip_header_extractor.v ../rtl/udp_header_extractor.v ../rtl/realigner.v ../rtl/moldudp64_ITCH_parser.v ../rtl/message_extractor.v ../tb/moldudp64_ITCH_parser/moldudp64_ITCH_parser_wrapper.v
  chparam -set BEAT_SIZE 64 -set PORT 16'h5678 moldudp64_ITCH_parser_wrapper
  synth_ecp5 -top moldudp64_ITCH_parser_wrapper -json build/$tag.json
  tee -o build/$tag.stat stat
"

nextpnr-ecp5 --85k --package CABGA381 --json build/$tag.json \
  --freq 300 --out-of-context -l build/$tag.nextpnr.log || true

grep -E "TRELLIS_FF|LUT4" build/$tag.stat || true
grep -i "max frequency" build/$tag.nextpnr.log | tail -1 || true
