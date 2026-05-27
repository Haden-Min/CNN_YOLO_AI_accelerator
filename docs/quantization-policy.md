# Quantization Policy

This project starts with a narrow, bit-exact policy for the first convolution
fixture. Later phases may extend the policy, but Phase 1 through Phase 3 should
change Python, RTL, fixtures, and documentation in the same commit whenever the
numeric policy changes.

## Tensor Layout

The initial tensor layout is CHW:

```text
input[c][h][w]
weight[oc][ic][kh][kw]
output[oc][oh][ow]
```

Flattening is row-major:

```text
input index  = c * H * W + h * W + w
weight index = oc * IC * KH * KW + ic * KH * KW + kh * KW + kw
output index = oc * OH * OW + oh * OW + ow
```

## Numeric Types

| Value | Type | Range | Phase 1 role |
| --- | --- | --- | --- |
| Input activation | signed INT8 | -128 to 127 | source fixture |
| Weight | signed INT8 | -128 to 127 | source fixture |
| Bias | signed INT32 | INT32 range | added before output write |
| Accumulator | signed INT32 | INT32 range | Phase 1 comparison target |
| Output activation | signed INT8 | -128 to 127 | Phase 3 comparison target |

## Zero Points

Phase 1 uses symmetric INT8:

```text
input_zero_point  = 0
weight_zero_point = 0
output_zero_point = 0
```

## Accumulator Equation

For each output element:

```text
acc[oc, oh, ow] =
    bias[oc]
    + sum_ic sum_kh sum_kw input[ic, ih, iw] * weight[oc, ic, kh, kw]
```

with:

```text
ih = oh * stride + kh - padding
iw = ow * stride + kw - padding
```

Phase 1 and Phase 2 compare only `expected_acc_int32`. Requantization,
saturation, and activation are intentionally left for Phase 3.
