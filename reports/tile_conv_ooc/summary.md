# 28x28 Tile Convolution OOC Result

- Tool: Vivado 2024.1
- Device: XC7Z020CLG400-1
- Design: `top_single_conv_tile_axi`
- Clock: 100 MHz (`10.000 ns`), user uncertainty `0.200 ns`
- State: out-of-context routed

## Timing

| Metric | Result |
| --- | ---: |
| WNS | `+1.138 ns` |
| TNS | `0.000 ns` |
| Setup failing endpoints | `0 / 2293` |
| WHS | `+0.011 ns` |
| THS | `0.000 ns` |
| Hold failing endpoints | `0 / 2293` |
| Unconstrained internal endpoints | `0` |

The longest setup path is from one replicated weight RAM output to a multiplier
stage register. Its data-path delay is `8.640 ns` with 7 logic levels. The
3-row line buffer is not the limiting timing path.

## Utilization

| Resource | Used |
| --- | ---: |
| LUT | `1031` |
| Logic LUT | `989` |
| LUTRAM | `42` |
| FF | `705` |
| RAMB18 | `9` |
| RAMB36 | `0` |
| DSP | `0` |

The 16-word output FIFO uses 24 LUTRAMs and 13 FFs. The three-row line buffer
uses 18 LUTRAMs and 52 FFs. The nine parallel weight-read lanes use nine
RAMB18 blocks.

## Scope

This validates internal timing after OOC placement and routing. It intentionally
does not model final AXI port delays or the PS FCLK buffer location. Run full
block-design implementation after connecting the Zynq PS, AXI DMA, AXI
interconnect, reset controller, and this accelerator IP.
