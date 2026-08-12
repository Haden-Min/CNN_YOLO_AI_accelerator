# 16x16 Tile Convolution OOC Result

- Tool: Vivado 2024.1
- Device: XC7Z020CLG400-1
- Design: `top_single_conv_tile_axi_16`
- Clock: 100 MHz (`10.000 ns`), user uncertainty `0.200 ns`
- State: out-of-context routed

## Timing

| Metric | Result |
| --- | ---: |
| WNS | `+1.258 ns` |
| TNS | `0.000 ns` |
| Setup failing endpoints | `0 / 2219` |
| WHS | `+0.009 ns` |
| THS | `0.000 ns` |
| Hold failing endpoints | `0 / 2219` |
| Unconstrained internal endpoints | `0` |

The longest setup path is from one replicated weight RAM output to a multiplier
stage register. Its data-path delay is `8.567 ns` with 8 logic levels. The
3-row line buffer is not the limiting timing path.

## Utilization

| Resource | Used |
| --- | ---: |
| LUT | `1020` |
| Logic LUT | `978` |
| LUTRAM | `42` |
| FF | `691` |
| RAMB18 | `9` |
| RAMB36 | `0` |
| DSP | `0` |

## Scope

This validates internal timing after OOC placement and routing. It does not
model final AXI port delays or the PS FCLK buffer location. Run full block-design
implementation after connecting the Zynq PS, DMA, and interconnect.
