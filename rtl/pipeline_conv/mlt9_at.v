`timescale 1ns/1ps

module mlt9_at #(
    parameter DATA_WIDTH = 8,
    parameter MUL_WIDTH  = 16,
    parameter ACC_WIDTH  = 32
)(
    input wire signed [9*DATA_WIDTH-1:0] input_window_i,
    input wire signed [9*DATA_WIDTH-1:0] weight_window_i,

    output wire signed [ACC_WIDTH-1:0] sum_o
);

wire signed [DATA_WIDTH-1:0] input_lane_w  [0:8];
wire signed [DATA_WIDTH-1:0] weight_lane_w [0:8];
wire signed [MUL_WIDTH-1:0]  mul_lane_w    [0:8];

genvar lane;
generate
    for (lane = 0; lane < 9; lane = lane + 1) begin : gen_mlt_lane
        assign input_lane_w[lane] =
            input_window_i[(lane+1)*DATA_WIDTH-1:lane*DATA_WIDTH];
        assign weight_lane_w[lane] =
            weight_window_i[(lane+1)*DATA_WIDTH-1:lane*DATA_WIDTH];

        mlt #(
            .DATA_WIDTH(DATA_WIDTH)
        ) u_mlt (
            .data_i(input_lane_w[lane]),
            .kernel_i(weight_lane_w[lane]),
            .mul_o(mul_lane_w[lane])
        );
    end
endgenerate

at #(
    .IN_WIDTH(MUL_WIDTH),
    .OUT_WIDTH(ACC_WIDTH)
) u_at (
    .mul0_i(mul_lane_w[0]),
    .mul1_i(mul_lane_w[1]),
    .mul2_i(mul_lane_w[2]),
    .mul3_i(mul_lane_w[3]),
    .mul4_i(mul_lane_w[4]),
    .mul5_i(mul_lane_w[5]),
    .mul6_i(mul_lane_w[6]),
    .mul7_i(mul_lane_w[7]),
    .mul8_i(mul_lane_w[8]),
    .sum_o(sum_o)
);

endmodule
