# A Simple FPGA Market Data Pipeline

# Testing the Skid Buffer Module

All run with DATA_WIDTH=64 using Yosys and ECP5, combinational input-to-output paths are not included in Fmax numbers.
|                             | LUT4s | FFs | Fmax after Routing/MHz | Critical Path           |
|-----------------------------|-------|-----|------------------------|-------------------------|
| OPT_OUTREG=0 OPT_LOWPOWER=0 | 68    | 65  | 533.62                 | r_valid to r_data       |
| OPT_OUTREG=0 OPT_LOWPOWER=1 | 70    | 65  | 342.82                 | r_valid to r_data       |
| OPT_OUTREG=1 OPT_LOWPOWER=0 | 69    | 130 | 372.02                 | r_valid to o_data       |
| OPT_OUTREG=1 OPT_LOWPOWER=1 | 71    | 130 | 337.61                 | r_valid to r_data       |

