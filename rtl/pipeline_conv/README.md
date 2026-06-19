# Phase 2 Pipeline Convolution

This is the active Phase 2 single-convolution PL path.

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
  returns `result_valid/result_addr/result_o` when an output is ready
- `top_single_conv_pipeline.v`: connects control, memory, and datapath

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
- OPT writes only when `result_valid` is asserted with the matching result tag
- the FSM no longer waits for every output result; it issues the next output
  after `mac_last` and uses `WRITE_OUT` only to drain the final in-flight result
- ATV is instantiated as an optional activation stage, but defaults to bypass
  for the current golden-model comparison

For the Phase 2 testbench, PS/DMA behavior is modeled as row bursts:

- preload the first 3 input rows into the line buffer
- start the accelerator
- stream the next input row after each output row is written
- read the final outputs back from `conv_output_mem`

This proves the line-buffered 3x3 flow for the current `IC=1`, `OC=1` fixture.
For multi-output-channel YOLO layers, the FSM loop order or input backpressure
needs to be extended so the same input window can be reused across all output
channels before the line buffer overwrites old rows.

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
