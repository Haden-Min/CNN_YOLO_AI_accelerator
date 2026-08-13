# 28x28 Serial-IC Tile OOC Summary

- Tool: Vivado 2024.1
- Device: XC7Z020CLG400-1
- Top: `top_single_conv_tile_axi`
- Constraint: 100 MHz, 0.2 ns clock uncertainty
- WNS: +1.234 ns
- TNS: 0.000 ns
- Setup failing endpoints: 0
- LUT: 1143
- FF: 838
- RAMB36: 1 (`tile_psum_buffer`)
- RAMB18: 9
- DSP: 0

The 676x32-bit partial-sum array was inferred as one RAMB36. This is an
out-of-context result; the complete PYNQ block design must be implemented and
timed separately.
