# RTL filelists

- `current/tile_conv_rtl.f`: production synthesis sources for
  `top_single_conv_tile_axi`.
- `current/*_tb.f`: production regression source lists.
- `legacy/`: archived full-frame and 16x16 experiment source lists.

All paths are relative to the repository root. Keep production and legacy
sources in separate filelists so Vivado cannot select an old `top_*` by
accident.
