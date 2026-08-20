`timescale 1ns/1ps

module at #(
    parameter IN_WIDTH  = 16,
    parameter OUT_WIDTH = 32 //일반적으로, 32bit 사용
)(
    input wire signed [IN_WIDTH-1:0] mul0_i,
    input wire signed [IN_WIDTH-1:0] mul1_i,
    input wire signed [IN_WIDTH-1:0] mul2_i,
    input wire signed [IN_WIDTH-1:0] mul3_i,
    input wire signed [IN_WIDTH-1:0] mul4_i,
    input wire signed [IN_WIDTH-1:0] mul5_i,
    input wire signed [IN_WIDTH-1:0] mul6_i,
    input wire signed [IN_WIDTH-1:0] mul7_i,
    input wire signed [IN_WIDTH-1:0] mul8_i,

    output wire signed [OUT_WIDTH-1:0] sum_o
);

wire signed [OUT_WIDTH-1:0] s0_0;
wire signed [OUT_WIDTH-1:0] s0_1;
wire signed [OUT_WIDTH-1:0] s0_2;
wire signed [OUT_WIDTH-1:0] s0_3;

wire signed [OUT_WIDTH-1:0] s1_0;
wire signed [OUT_WIDTH-1:0] s1_1;

wire signed [OUT_WIDTH-1:0] s2_0;

assign s0_0 = mul0_i + mul1_i; //첫 번째 트리 층
assign s0_1 = mul2_i + mul3_i;
assign s0_2 = mul4_i + mul5_i;
assign s0_3 = mul6_i + mul7_i;

assign s1_0 = s0_0 + s0_1; //두 번째 트리 층
assign s1_1 = s0_2 + s0_3;

assign s2_0 = s1_0 + s1_1; //세 번째 트리 층

assign sum_o = s2_0 + mul8_i; //최종 합

endmodule
