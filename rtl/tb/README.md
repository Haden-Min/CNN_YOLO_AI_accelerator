# RTL testbenches

- `current/` verifies the production 28x28 tile core, AXI wrapper, serial input
  channel accumulation, backpressure, and performance variants.
- `legacy/` preserves tests for the 16x16 wrappers, full-frame pipeline, and
  first single-convolution implementation.

The runnable source lists are grouped the same way under `rtl/filelists/`.
