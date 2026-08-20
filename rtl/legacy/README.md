# Legacy RTL

Nothing in this directory belongs to the production
`top_single_conv_tile_axi` hierarchy.

- `full_frame_pipeline/`: earlier 5x5/416x416 line-buffered pipeline and its
  former top modules.
- `tile_16_variants/`: fixed 16x16 wrappers kept for comparison experiments.
- `early_single_conv/`: first single-convolution implementation and primitives.
- `reference_primitives/`: unused SI/WBUF/weight-buffer experiments from the
  earlier pipeline direction.

Matching testbenches and filelists live under `rtl/tb/legacy/` and
`rtl/filelists/legacy/`. Do not add these files to the production Vivado source
set unless intentionally reproducing an archived experiment.
