# PS Runtime Software

Board-side software belongs here.

The PS runtime should:

- load input images and generated INT8 parameter files
- manage DDR buffers
- configure the PL accelerator
- launch data transfers
- collect feature maps
- run YOLO decode and NMS

Keep heavyweight CNN math in PL and keep orchestration/debugging in PS.
