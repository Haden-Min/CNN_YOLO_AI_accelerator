# Architecture

This project separates model preparation, runtime control, and CNN computation
into three clear layers.

## Offline Preparation

Offline tools run on the host computer before board execution.

- Parse `yolov3-tiny.cfg` and Darknet `.weights` files.
- Extract convolution, bias, and BatchNorm parameters.
- Fold BatchNorm into convolution weights and bias.
- Quantize folded parameters to INT8.
- Export layer parameter binaries and golden reference outputs.

This stage should be reproducible and versioned through scripts, but generated
weight binaries should stay out of Git.

## PS Runtime

The processing system is responsible for orchestration rather than heavy CNN
math.

- Load input images and quantized layer parameters.
- Run image preprocessing and layout conversion.
- Allocate and manage DDR buffers.
- Configure the PL accelerator through AXI-Lite registers.
- Move feature maps and weights through AXI DMA or memory-mapped interfaces.
- Schedule layers and collect output feature maps.
- Run YOLO decode, confidence filtering, and NMS.

Keeping decode and NMS on the PS reduces the initial PL design scope and makes
debugging faster.

## PL Accelerator

The programmable logic should focus on the repeated CNN datapath.

- Line and window buffering for 3x3 convolution.
- INT8 input and weight multiplication.
- INT32 accumulation.
- Bias add and requantization.
- Activation such as ReLU or LeakyReLU.
- Optional max-pooling.
- AXI-compatible input and output interfaces.

The first hardware target is a single convolution-layer block that can match a
Python golden model before it is chained into a larger pipeline.

## Initial Data Path

```text
DDR input feature map
-> AXI transfer
-> line/window buffer
-> INT8 MAC array
-> INT32 accumulator
-> bias / activation
-> requantization
-> optional MaxPool
-> DDR output feature map
```

## Verification Strategy

1. Generate a small deterministic input tensor and folded INT8 weights.
2. Compute the expected output in Python.
3. Run the same vectors through RTL simulation.
4. Compare exact values when possible, otherwise compare within the selected
   quantization tolerance.
5. Only then connect the block to PS/PL transfer logic.
