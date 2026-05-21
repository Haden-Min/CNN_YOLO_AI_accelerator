# RTL

New Verilog RTL belongs here.

Planned structure:

- `core/` for arithmetic and CNN datapath blocks
- `buffers/` for line buffers and window generators
- `interfaces/` for AXI-facing modules
- `top/` for integration wrappers
- `tb/` for simulation-only testbenches

Start small: one INT8 convolution layer that matches a Python golden model.
