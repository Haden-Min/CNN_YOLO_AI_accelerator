`timescale 1ns/1ps

module top_single_conv_pipeline #(
    parameter DATA_WIDTH = 8,
    parameter MUL_WIDTH  = 16,
    parameter ACC_WIDTH  = 32,
    parameter ACC_BANK_SIZE = 9,

    parameter IC      = 1,
    parameter OC      = 1,
    parameter IN_H    = 5,
    parameter IN_W    = 5,
    parameter K_H     = 3,
    parameter K_W     = 3,
    parameter STRIDE  = 1,
    parameter PADDING = 0,
    parameter OUT_H   = 3,
    parameter OUT_W   = 3,
    parameter ENABLE_OUTPUT_BUFFER = 1,

    parameter INPUT_SIZE  = IC * IN_H * IN_W,
    parameter WEIGHT_SIZE = OC * IC * K_H * K_W,
    parameter BIAS_SIZE   = OC,
    parameter OUTPUT_SIZE = OC * OUT_H * OUT_W,

    parameter INPUT_ADDR_WIDTH  = (INPUT_SIZE  <= 1) ? 1 : $clog2(INPUT_SIZE),
    parameter WEIGHT_ADDR_WIDTH = (WEIGHT_SIZE <= 1) ? 1 : $clog2(WEIGHT_SIZE),
    parameter BIAS_ADDR_WIDTH   = (BIAS_SIZE   <= 1) ? 1 : $clog2(BIAS_SIZE),
    parameter OUTPUT_ADDR_WIDTH = (OUTPUT_SIZE <= 1) ? 1 : $clog2(OUTPUT_SIZE),
    parameter OUT_H_WIDTH       = (OUT_H       <= 1) ? 1 : $clog2(OUT_H),
    parameter OUT_W_WIDTH       = (OUT_W       <= 1) ? 1 : $clog2(OUT_W)
)(
    input wire clk,
    input wire rst_n,
    input wire start_i,
    input wire output_ready_i,

    input wire input_load_en_i,
    input wire [INPUT_ADDR_WIDTH-1:0] input_load_addr_i,
    input wire signed [DATA_WIDTH-1:0] input_stream_data_i,

    input wire weight_load_en_i,
    input wire [WEIGHT_ADDR_WIDTH-1:0] weight_load_addr_i,
    input wire signed [DATA_WIDTH-1:0] weight_stream_data_i,

    input wire bias_load_en_i,
    input wire [BIAS_ADDR_WIDTH-1:0] bias_load_addr_i,
    input wire signed [ACC_WIDTH-1:0] bias_load_data_i,

    input wire [OUTPUT_ADDR_WIDTH-1:0] output_read_addr_i,

    output wire [BIAS_ADDR_WIDTH-1:0] bias_addr_o,
    output wire [OUTPUT_ADDR_WIDTH-1:0] output_addr_o,
    output wire output_we_o,
    output wire busy_o,
    output wire done_o,

    output wire signed [ACC_WIDTH-1:0] output_data_o,
    output wire signed [ACC_WIDTH-1:0] output_read_data_o
);

wire [INPUT_ADDR_WIDTH-1:0] control_input_base_addr_w;
wire [WEIGHT_ADDR_WIDTH-1:0] control_weight_base_addr_w;
wire [OUTPUT_ADDR_WIDTH-1:0] control_output_addr_w;
wire control_output_we_w;
wire acc_load_bias_w;
wire mac_en_w;
wire mac_last_w;
wire input_window_valid_w;
wire input_window_req_w;

wire signed [K_H*K_W*DATA_WIDTH-1:0] input_window_w;
wire signed [K_H*K_W*DATA_WIDTH-1:0] weight_window_w;
wire signed [ACC_WIDTH-1:0] bias_data_w;
wire signed [ACC_WIDTH-1:0] acc_w;
wire datapath_result_valid_w;
wire [OUTPUT_ADDR_WIDTH-1:0] datapath_result_addr_w;
wire signed [ACC_WIDTH-1:0] datapath_result_data_w;
wire datapath_busy_w;

conv_control_unit #(
    .DATA_WIDTH(DATA_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .IC(IC),
    .OC(OC),
    .IN_H(IN_H),
    .IN_W(IN_W),
    .K_H(K_H),
    .K_W(K_W),
    .STRIDE(STRIDE),
    .PADDING(PADDING),
    .OUT_H(OUT_H),
    .OUT_W(OUT_W),
    .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH),
    .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
    .BIAS_ADDR_WIDTH(BIAS_ADDR_WIDTH),
    .OUTPUT_ADDR_WIDTH(OUTPUT_ADDR_WIDTH)
) u_control_unit (
    .clk(clk),
    .rst_n(rst_n),
    .start_i(start_i),
    .input_window_valid_i(input_window_valid_w),
    .datapath_result_valid_i(datapath_result_valid_w),
    .datapath_result_ready_i(output_ready_i),
    .datapath_result_addr_i(datapath_result_addr_w),
    .input_base_addr_o(control_input_base_addr_w),
    .weight_base_addr_o(control_weight_base_addr_w),
    .bias_addr_o(bias_addr_o),
    .output_addr_o(control_output_addr_w),
    .busy_o(busy_o),
    .done_o(done_o),
    .input_window_req_o(input_window_req_w),
    .output_we_o(control_output_we_w),
    .mac_en_o(mac_en_w),
    .mac_last_o(mac_last_w),
    .acc_load_bias_o(acc_load_bias_w)
);

conv_memory_unit #(
    .DATA_WIDTH(DATA_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .IC(IC),
    .OC(OC),
    .IN_H(IN_H),
    .IN_W(IN_W),
    .K_H(K_H),
    .K_W(K_W),
    .STRIDE(STRIDE),
    .PADDING(PADDING),
    .OUT_H(OUT_H),
    .OUT_W(OUT_W),
    .ENABLE_OUTPUT_BUFFER(ENABLE_OUTPUT_BUFFER),
    .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH),
    .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
    .BIAS_ADDR_WIDTH(BIAS_ADDR_WIDTH),
    .OUTPUT_ADDR_WIDTH(OUTPUT_ADDR_WIDTH)
) u_memory_unit (
    .clk(clk),
    .rst_n(rst_n),
    .input_load_en_i(input_load_en_i),
    .input_load_addr_i(input_load_addr_i),
    .input_load_data_i(input_stream_data_i),
    .weight_load_en_i(weight_load_en_i),
    .weight_load_addr_i(weight_load_addr_i),
    .weight_load_data_i(weight_stream_data_i),
    .bias_load_en_i(bias_load_en_i),
    .bias_load_addr_i(bias_load_addr_i),
    .bias_load_data_i(bias_load_data_i),
    .input_base_addr_i(control_input_base_addr_w),
    .input_window_req_i(input_window_req_w),
    .weight_base_addr_i(control_weight_base_addr_w),
    .bias_read_addr_i(bias_addr_o),
    .output_write_en_i(datapath_result_valid_w && output_ready_i),
    .output_write_addr_i(datapath_result_addr_w),
    .output_write_data_i(datapath_result_data_w),
    .output_read_addr_i(output_read_addr_i),
    .input_window_o(input_window_w),
    .input_window_valid_o(input_window_valid_w),
    .weight_window_o(weight_window_w),
    .bias_data_o(bias_data_w),
    .output_read_data_o(output_read_data_o)
);

conv_datapath #(
    .DATA_WIDTH(DATA_WIDTH),
    .MUL_WIDTH(MUL_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .K_H(K_H),
    .K_W(K_W),
    .OUTPUT_ADDR_WIDTH(OUTPUT_ADDR_WIDTH),
    .ACC_BANK_SIZE(ACC_BANK_SIZE)
) u_datapath (
    .clk(clk),
    .rst_n(rst_n),
    .acc_load_bias_i(acc_load_bias_w),
    .mac_en_i(mac_en_w),
    .mac_last_i(mac_last_w),
    .output_addr_i(control_output_addr_w),
    .result_ready_i(output_ready_i),
    .input_window_i(input_window_w),
    .weight_window_i(weight_window_w),
    .bias_i(bias_data_w),
    .acc_o(acc_w),
    .result_valid_o(datapath_result_valid_w),
    .result_addr_o(datapath_result_addr_w),
    .result_o(datapath_result_data_w),
    .busy_o(datapath_busy_w)
);

assign output_we_o   = datapath_result_valid_w;
assign output_addr_o = datapath_result_valid_w ? datapath_result_addr_w : control_output_addr_w;
assign output_data_o = datapath_result_data_w;

endmodule
