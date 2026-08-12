# Tile Size Comparison Summary

| Metric | 28x28 | 16x16 |
| --- | ---: | ---: |
| Input/output pixels | 784 / 676 | 256 / 196 |
| AXI cycles per tile | 5701 | 1729 |
| Latency at 100 MHz | 57.01 us | 17.29 us |
| Cycles per output | 8.433 | 8.821 |
| Output throughput | 11.858 Moutput/s | 11.336 Moutput/s |
| WNS | +1.138 ns | +1.258 ns |
| LUT | 1031 | 1020 |
| FF | 705 | 691 |
| LUTRAM / RAMB18 / DSP | 42 / 9 / 0 | 42 / 9 / 0 |

Recommendation: keep 28x28 as the default single-core tile. Use 16x16 when
single-tile latency or small buffers matter more than whole-feature-map
efficiency.
