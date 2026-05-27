# First Milestone PASS Criteria

The first milestone proves one deterministic INT8 convolution fixture before
any RTL optimization, YOLO integration, or board work begins.

## Phase 1 Scope

Phase 1 owns the Python golden model and shared fixture files:

- `sw/fixture/single_conv_001/layer_config.json`
- `sw/fixture/single_conv_001/input_int8.hex`
- `sw/fixture/single_conv_001/weight_int8.hex`
- `sw/fixture/single_conv_001/bias_int32.hex`
- `sw/fixture/single_conv_001/expected_acc_int32.hex`
- `sw/golden/model/conv2d_int8_reference.py`
- `sw/golden/script/generate_single_conv_fixture.py`
- `sw/golden/script/generate_rtl_mem.py`
- `tests/rtl/compare_conv_output.py`

## Required Commands

Run these from the repository root:

```powershell
python sw/golden/script/generate_single_conv_fixture.py --fixture single_conv_001
python sw/golden/model/conv2d_int8_reference.py --fixture sw/fixture/single_conv_001
python sw/golden/script/generate_rtl_mem.py --fixture sw/fixture/single_conv_001
python tests/rtl/compare_conv_output.py --fixture sw/fixture/single_conv_001 --actual sw/fixture/single_conv_001/expected_acc_int32.hex
```

## PASS Definition

Phase 1 passes when all of the following are true:

1. `layer_config.json` describes `single_conv_001` as CHW, IC=1, OC=1,
   H=W=5, KH=KW=3, stride=1, padding=0.
2. The golden model reports that computed output shape matches the configured
   output shape `[1, 3, 3]`.
3. `expected_acc_int32.hex` exists and contains exactly 9 signed INT32 values.
4. Re-running the fixture generator produces byte-identical fixture files.
5. The compare script can report `Mismatch count: 0` when comparing the
   expected accumulator against itself.

Do not start Phase 2 RTL work until these checks pass.
