# RTL

This directory keeps the active Phase 2 single-conv design separate from the
fixed legacy/reference files that were already in the repository.

Use these filelists as the source of truth for the current Vivado project:

- `rtl/filelists/phase2_pipeline_rtl.f`: synthesizable RTL only
- `rtl/filelists/phase2_pipeline_tb.f`: RTL plus the PS/PL-style testbench

Current active hierarchy:

```text
top_single_conv_pipeline
  conv_control_unit
    single_conv_fsm
  conv_memory_unit
    conv_input_mem
      conv_input_line_buffer
      conv_window_buffer
    conv_weight_mem
    conv_bias_mem
    conv_output_mem
  conv_datapath
    gen_mlt_lane[*].mlt
    at
    gen_acc_bank[0..8].acc
    activation
```

Fixed legacy/reference files are not part of new development. Do not add new
modules there, and do not add these files to the Phase 2 Vivado project unless
you are intentionally restoring that older path:

- `rtl/single_conv/`
- `rtl/pipeline_conv/si.v`
- `rtl/pipeline_conv/wbuf.v`
- `rtl/pipeline_conv/weight_buffer_9.v`
- root-level `rtl/si.v`, `rtl/wbuf.v`, `rtl/at.v`
