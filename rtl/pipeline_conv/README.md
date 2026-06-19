# Phase 2 Pipeline Convolution

This is the active Phase 2 single-convolution PL path.

The design is split explicitly into:

- `conv_control_unit.v`: wraps `single_conv_fsm` and aligns control pulses for
  synchronous memory reads
- `conv_memory_unit.v`: groups input, weight, bias, and output memories
- `conv_datapath.v`: contains the 3x3 parallel multiply/add tree and accumulator
- `top_single_conv_pipeline.v`: connects control, memory, and datapath

The current datapath computes one output pixel at a time. Inside each output,
the 3x3 kernel multiplies run in parallel through `mlt9_at`, then accumulate
with bias through `acc`.

Not part of the active Phase 2 path right now:

- `si.v`
- `wbuf.v`
- `weight_buffer_9.v`
- `activation.v`

Those are fixed reference files from the earlier pipeline direction. New RTL
should stay in the active Phase 2 path instead of being added to that reference
set. The current golden-model proof uses BRAM-style memories driven by the
PS/PL-style testbench.
