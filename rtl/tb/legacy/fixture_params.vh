`ifndef FIXTURE_PARAMS_VH
`define FIXTURE_PARAMS_VH

`define FIXTURE_ID "single_conv_001"
`define FIXTURE_IC 1
`define FIXTURE_OC 1
`define FIXTURE_INPUT_H 5
`define FIXTURE_INPUT_W 5
`define FIXTURE_KERNEL_H 3
`define FIXTURE_KERNEL_W 3
`define FIXTURE_OUTPUT_H 3
`define FIXTURE_OUTPUT_W 3
`define FIXTURE_STRIDE 1
`define FIXTURE_PADDING 0
`define FIXTURE_INPUT_SIZE 25
`define FIXTURE_WEIGHT_SIZE 9
`define FIXTURE_BIAS_SIZE 1
`define FIXTURE_OUTPUT_SIZE 9

`define FIXTURE_INPUT_MEM "sw/fixture/generated/single_conv_001/input_int8.mem"
`define FIXTURE_WEIGHT_MEM "sw/fixture/generated/single_conv_001/weight_int8.mem"
`define FIXTURE_BIAS_MEM "sw/fixture/generated/single_conv_001/bias_int32.mem"
`define FIXTURE_EXPECTED_ACC_MEM "sw/fixture/generated/single_conv_001/expected_acc_int32.mem"

`endif
