# Phase 2 Pipeline Convolution

This is the active Phase 2 single-convolution PL path.

## 28x28 board-bring-up tile path

The current deployment candidate is a separate fixed tile architecture:

- `tile_input_loader.v`: accepts exactly one 28x28 INT8 tile and writes three
  circular row banks
- `tile_line_buffer_3row.v`: stores only 3x28 pixels
- `tile_window_generator_3x3.v`: emits 26 windows per output row while obeying
  ready/valid backpressure
- `tile_conv_controller.v`: alternates initial-three-row load, output-row
  compute, and one-next-row load
- `top_single_conv_tile.v`: reuses `conv_weight_mem`, `conv_bias_mem`, and
  `conv_datapath` for one IC=1, OC=1 valid 3x3 convolution
- `tile_psum_buffer.v`: stores one INT32 partial sum per output position in
  BRAM while input channels are processed serially
- `top_single_conv_tile_axi.v`: uses distinct 10-word parameter and 784-word
  tile packets for every input channel, then returns 676 accumulated INT32
  results through `axis_output_fifo` only after the final input channel

The full interface, register map, verification results, and limitations are in
[`../../docs/28x28-tile-conv-design.md`](../../docs/28x28-tile-conv-design.md).
Serial input-channel accumulation is documented in
[`../../docs/multi-input-channel-accumulation.md`](../../docs/multi-input-channel-accumulation.md).

The fixed 16x16 alternative uses `top_single_conv_tile_16.v` and
`top_single_conv_tile_axi_16.v`. It accepts 256 pixels and returns 196 results.
See
[`../../docs/tile-size-comparison-28-vs-16.md`](../../docs/tile-size-comparison-28-vs-16.md)
for the measured comparison. The generic lower modules are shared, while the
16x16 files provide an independent fixed synthesis/IP entry point.

The design is split explicitly into:

- `conv_control_unit.v`: wraps `single_conv_fsm`, including the `WAIT_WINDOW`
  state used while the input line buffer is not ready
- `conv_memory_unit.v`: groups the input line/window buffer with weight, bias,
  and output memories
- `conv_input_mem.v`: connects `conv_input_line_buffer` and
  `conv_window_buffer` so the datapath sees a stable 3x3 input window
- `conv_window_buffer.v`: reloads a full window at output-row starts, then
  shifts the previous window by `STRIDE` columns and appends only the new
  right-side columns while staying on the same input row
- `conv_datapath.v`: contains the hazard-safe MLT/AT/ACC_BANK/ATV pipeline and
  returns a backpressure-safe `result_valid/result_ready/result_o` transaction
  when an output is ready
- `axis_output_fifo.v`: decouples completed core results from DMA
  `M_AXIS_TREADY` backpressure
- `top_single_conv_pipeline.v`: connects control, memory, and datapath
- `top_single_conv_pipeline_axi.v`: wraps `top_single_conv_pipeline` with
  AXI-Lite control/status plus AXI-Stream input/output ports for the PYNQ DMA
  integration path

The current datapath maps each issued output to one of 9 accumulator banks with
`output_addr % 9`. Inside each output, the 3x3 kernel multiplies run in
parallel, then the registered multiplier products feed a registered adder-tree
sum and the tagged accumulator bank. The final write is driven by datapath
`result_valid`, not by a fixed FSM latency assumption.

Pipeline hazard control:

- SI/WBUF uses `input_window_req` and `input_window_valid` so the FSM waits
  until a valid 3x3 window is available
- MLT/AT/ACC carry valid bits plus `mac_last` and `output_addr` tags through
  the pipeline
- ACC_BANK holds independent partial sums in 9 `acc` instances, so a later
  output's bias load does not overwrite an earlier output still in flight
- OPT transfers only on `result_valid && result_ready`; result data and address
  remain stable while the downstream FIFO is full
- the FSM no longer waits for every output result; it issues the next output
  after `mac_last` and uses `WRITE_OUT` only to drain the final in-flight result
- ATV is instantiated as an optional activation stage, but defaults to bypass
  for the current golden-model comparison

For the Phase 2 testbench, PS/DMA behavior is modeled as row bursts:

- preload the first 3 input rows into the line buffer
- start the accelerator
- stream the next input row after each output row is written
- compare the result transactions emitted by the core

This proves the line-buffered 3x3 flow for the current `IC=1`, `OC=1` fixture.
For multi-output-channel YOLO layers, the FSM loop order or input backpressure
needs to be extended so the same input window can be reused across all output
channels before the line buffer overwrites old rows.

The AXI wrapper keeps the same row-burst behavior but turns it into a DMA-style
stream contract:

- each non-final input channel updates the output-position partial sums in one
  BRAM36; only final-channel INT32 results are pushed into the 16-word FIFO
- `M_AXIS_TVALID`, `TDATA`, and `TLAST` remain stable while
  `M_AXIS_TREADY=0`
- the core stalls safely if both the FIFO and its one-word result holding
  register are occupied
- transaction done is asserted only after the final `M_AXIS` word and `TLAST`
  are accepted

| AXI-Lite offset | Meaning |
| --- | --- |
| `0x00` | control: bit 0 starts one transaction, bit 1 clears done, bit 2 soft-resets wrapper state |
| `0x04` | status bits plus wrapper state |
| `0x08` | accepted input stream words |
| `0x0c` | produced output stream words |
| `0x10` | expected input stream words |
| `0x14` | expected output stream words |
| `0x18` | error flags |
| `0x1c` | parameter words per input channel (`10`) |
| `0x20` | total serial input-channel count (`1..1024`) |
| `0x24` | current 0-based input-channel index |

For the current 416x416 fixture, one MM2S input payload contains 173066 32-bit
stream words: 173056 INT8 input words in row order, 9 INT8 weight words, and 1
INT32 bias word. INT8 values are carried in `s_axis_tdata[7:0]`; bias uses all
32 bits. The S2MM output stream returns 171396 INT32 accumulator words and
asserts `m_axis_tlast` on the final word.

The 416x416 AXI regression intentionally drives 120 cycles of output
backpressure in every 200-cycle interval. It checks that output begins before
the input packet has finished, then compares all 171396 words and the final
`TLAST`. Vivado Simulator 2024.1 reports:

```text
PASS: tb_single_conv_pipeline_axi_v2_416 outputs=171396 stream_in=173066 status=0x00008011
```

Current input-window reuse behavior:

- `STRIDE=1`: reuse 2 columns from the previous 3x3 window, append 1 new column
- `STRIDE=2`: reuse 1 column from the previous 3x3 window, append 2 new columns
- row/channel change: reload the full 3x3 window from the line buffer

Not part of the active Phase 2 path right now:

- `si.v`
- `wbuf.v`
- `weight_buffer_9.v`

Those are fixed reference files from the earlier pipeline direction. New RTL
should stay in the active Phase 2 path instead of being added to that reference
set.
