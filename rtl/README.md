# RTL source layout

The production synthesis top is:

```text
rtl/active/top_single_conv_tile_axi.v
```

Use `top_single_conv_tile_axi` as the Vivado top module. The similarly named
files under `rtl/legacy/` are preserved alternatives or earlier architectures;
they are not part of the production source set.

## Directory map

```text
rtl/
|-- active/                 Production 28x28 tile accelerator
|   |-- top_single_conv_tile_axi.v
|   |-- core/               Tile scheduling and the internal tile core
|   |-- datapath/           Multiply, adder tree, accumulator, activation
|   |-- memory/             Tile/weight/bias/partial-sum storage
|   |-- interface/          AXI-Stream output FIFO
|   `-- integration/        Optional Vivado IP packaging shell
|-- tb/
|   |-- current/            Tests for the production design
|   `-- legacy/             Tests for archived implementations
|-- filelists/
|   |-- current/            Production build and regression filelists
|   `-- legacy/             Archived design filelists
`-- legacy/                 Non-production synthesizable RTL
```

The production-only source list is
`rtl/filelists/current/tile_conv_rtl.f`. It deliberately excludes the optional
IP packaging shell and every legacy top. Vivado IP packaging adds
`rtl/active/integration/cnn_tile_accel_ip.v` separately.

## Production hierarchy

```text
top_single_conv_tile_axi
|-- top_single_conv_tile
|   |-- tile_conv_controller
|   |-- tile_input_loader
|   |-- tile_line_buffer_3row
|   |-- tile_window_generator_3x3
|   |-- conv_weight_mem
|   |-- conv_bias_mem
|   `-- conv_datapath
|       |-- mlt[*]
|       |-- at
|       |-- acc[*]
|       `-- activation
|-- tile_psum_buffer
`-- axis_output_fifo
```

`cnn_tile_accel_ip` is only a fixed-parameter shell used by the Vivado IP
packaging flow. It wraps the production top but is not the accelerator's
canonical RTL top.

## Tests

From the repository root, run the current regression suite with:

```powershell
powershell -ExecutionPolicy Bypass -File vivado/run_rtl_tests.ps1
```

The test script compiles only filelists under `rtl/filelists/current/`.
