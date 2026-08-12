`timescale 1ns/1ps

module top_single_conv_tile_16 #(
    parameter DATA_WIDTH = 8,
    parameter MUL_WIDTH = 16,
    parameter ACC_WIDTH = 32,
    parameter WEIGHT_ADDR_WIDTH = 4
)(
    input wire clk,
    input wire rst_n,
    input wire start_i,

    input wire signed [DATA_WIDTH-1:0] s_data_i,
    input wire s_valid_i,
    output wire s_ready_o,
    input wire s_last_i,

    input wire weight_load_en_i,
    input wire [WEIGHT_ADDR_WIDTH-1:0] weight_load_addr_i,
    input wire signed [DATA_WIDTH-1:0] weight_load_data_i,
    input wire bias_load_en_i,
    input wire signed [ACC_WIDTH-1:0] bias_load_data_i,

    output wire signed [ACC_WIDTH-1:0] result_data_o,
    output wire [7:0] result_addr_o,
    output wire result_last_o,
    output wire result_valid_o,
    input wire result_ready_i,

    output wire busy_o,
    output wire done_o,
    output wire [1:0] input_error_o,
    output wire [3:0] state_o
);

top_single_conv_tile #(
    .DATA_WIDTH(DATA_WIDTH),
    .MUL_WIDTH(MUL_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .TILE_WIDTH(16),
    .TILE_HEIGHT(16),
    .OUTPUT_WIDTH(14),
    .OUTPUT_HEIGHT(14),
    .OUTPUT_SIZE(196),
    .COL_WIDTH(4),
    .OUTPUT_ADDR_WIDTH(8),
    .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
) u_tile_16 (
    .clk(clk),
    .rst_n(rst_n),
    .start_i(start_i),
    .s_data_i(s_data_i),
    .s_valid_i(s_valid_i),
    .s_ready_o(s_ready_o),
    .s_last_i(s_last_i),
    .weight_load_en_i(weight_load_en_i),
    .weight_load_addr_i(weight_load_addr_i),
    .weight_load_data_i(weight_load_data_i),
    .bias_load_en_i(bias_load_en_i),
    .bias_load_data_i(bias_load_data_i),
    .result_data_o(result_data_o),
    .result_addr_o(result_addr_o),
    .result_last_o(result_last_o),
    .result_valid_o(result_valid_o),
    .result_ready_i(result_ready_i),
    .busy_o(busy_o),
    .done_o(done_o),
    .input_error_o(input_error_o),
    .state_o(state_o)
);

endmodule
