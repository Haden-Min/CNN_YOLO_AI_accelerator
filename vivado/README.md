# Vivado 2024.1 automation

This directory contains the reproducible PYNQ-Z2 custom-IP, block-design, RTL
test, and bitstream flow. Generated projects are written below `build/` and are
not committed.

The primary board-bring-up path uses the Vivado 2024.1 GUI. Start Vivado with no
project open, then enter these commands in the Tcl Console:

```tcl
cd {C:/path/to/CNN_YOLO_AI_accelerator}
source ./vivado/create_pynq_z2_project.tcl
```

After `CNN_GUI: PASS`, click **Flow Navigator > Generate Bitstream**. When it
finishes, return to the Tcl Console:

```tcl
source ./vivado/export_pynq_jupyter_package.tcl
```

This creates the two browser-upload files under `build/pynq_upload/`: a Jupyter
notebook and a ZIP containing the overlay and both test fixtures. PowerShell
scripts remain available as an optional headless regression path.

See [`../docs/pynq-z2-reproduction-guide.md`](../docs/pynq-z2-reproduction-guide.md)
for prerequisites, the exact block diagram, pass criteria, and board commands.
