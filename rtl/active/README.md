# Active RTL

`top_single_conv_tile_axi.v` is the canonical production top. Lower-level
modules are grouped by responsibility so that no other file named `top_*`
appears beside it:

- `core/`: the internal tile core and controller.
- `datapath/`: arithmetic pipeline modules.
- `memory/`: input, parameter, line, and partial-sum storage.
- `interface/`: stream buffering.
- `integration/`: optional packaging-only shell.

Use `../filelists/current/tile_conv_rtl.f` for synthesis.
