`timescale 1ns/1ps

module conv_datapath #(
    parameter DATA_WIDTH = 8,
    parameter MUL_WIDTH  = 16,
    parameter ACC_WIDTH  = 32,
    parameter K_H        = 3,
    parameter K_W        = 3
)(
    input wire clk,
    input wire rst_n,

    input wire acc_load_bias_i,
    input wire mac_en_i,

    input wire signed [K_H*K_W*DATA_WIDTH-1:0] input_window_i,
    input wire signed [K_H*K_W*DATA_WIDTH-1:0] weight_window_i,
    input wire signed [ACC_WIDTH-1:0] bias_i,

    output wire signed [ACC_WIDTH-1:0] acc_o
);

wire signed [ACC_WIDTH-1:0] mac_sum_w;

mlt9_at #(
    .DATA_WIDTH(DATA_WIDTH),
    .MUL_WIDTH(MUL_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
) u_mlt9_at (
    .input_window_i(input_window_i),
    .weight_window_i(weight_window_i),
    .sum_o(mac_sum_w)
);

acc #(
    .IN_WIDTH(ACC_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
) u_acc (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(1'b0),
    .load_bias_i(acc_load_bias_i),
    .en_i(mac_en_i),
    .data_i(mac_sum_w),
    .bias_i(bias_i),
    .acc_o(acc_o)
);

endmodule
