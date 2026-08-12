`timescale 1ns/1ps

module top_single_conv_tile #(
    parameter DATA_WIDTH        = 8,
    parameter MUL_WIDTH         = 16,
    parameter ACC_WIDTH         = 32,
    parameter TILE_WIDTH        = 28,
    parameter TILE_HEIGHT       = 28,
    parameter OUTPUT_WIDTH      = TILE_WIDTH - 2,
    parameter OUTPUT_HEIGHT     = TILE_HEIGHT - 2,
    parameter OUTPUT_SIZE       = OUTPUT_WIDTH * OUTPUT_HEIGHT,
    parameter COL_WIDTH         = (TILE_WIDTH <= 1) ? 1 : $clog2(TILE_WIDTH),
    parameter OUTPUT_ADDR_WIDTH = (OUTPUT_SIZE <= 1) ? 1 : $clog2(OUTPUT_SIZE),
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
    output wire [OUTPUT_ADDR_WIDTH-1:0] result_addr_o,
    output wire result_last_o,
    output wire result_valid_o,
    input wire result_ready_i,

    output wire busy_o,
    output wire done_o,
    output wire [1:0] input_error_o,
    output wire [3:0] state_o
);

wire loader_start_w;
wire loader_enable_w;
wire loader_write_en_w;
wire [1:0] loader_write_bank_w;
wire [COL_WIDTH-1:0] loader_write_col_w;
wire signed [DATA_WIDTH-1:0] loader_write_data_w;
wire loader_row_done_w;

wire line_read_en_w;
wire [1:0] line_top_bank_w;
wire [COL_WIDTH-1:0] line_read_col_w;
wire signed [3*DATA_WIDTH-1:0] line_column_w;
wire line_column_valid_w;

wire window_start_row_w;
wire window_column_ready_w;
wire signed [9*DATA_WIDTH-1:0] input_window_w;
wire window_valid_w;
wire window_ready_w;

wire acc_load_bias_w;
wire mac_en_w;
wire mac_last_w;
wire [OUTPUT_ADDR_WIDTH-1:0] issue_output_addr_w;

wire signed [9*DATA_WIDTH-1:0] weight_window_w;
wire signed [ACC_WIDTH-1:0] bias_data_w;
tile_input_loader #(
    .DATA_WIDTH(DATA_WIDTH),
    .TILE_WIDTH(TILE_WIDTH),
    .TILE_HEIGHT(TILE_HEIGHT),
    .COL_WIDTH(COL_WIDTH)
) u_input_loader (
    .clk(clk),
    .rst_n(rst_n),
    .start_i(loader_start_w),
    .load_enable_i(loader_enable_w),
    .s_data_i(s_data_i),
    .s_valid_i(s_valid_i),
    .s_ready_o(s_ready_o),
    .s_last_i(s_last_i),
    .write_en_o(loader_write_en_w),
    .write_bank_o(loader_write_bank_w),
    .write_col_o(loader_write_col_w),
    .write_data_o(loader_write_data_w),
    .row_done_o(loader_row_done_w),
    .tile_done_o(),
    .active_o(),
    .error_o(input_error_o)
);

tile_line_buffer_3row #(
    .DATA_WIDTH(DATA_WIDTH),
    .TILE_WIDTH(TILE_WIDTH),
    .COL_WIDTH(COL_WIDTH)
) u_line_buffer (
    .clk(clk),
    .rst_n(rst_n),
    .write_en_i(loader_write_en_w),
    .write_bank_i(loader_write_bank_w),
    .write_col_i(loader_write_col_w),
    .write_data_i(loader_write_data_w),
    .read_en_i(line_read_en_w),
    .top_bank_i(line_top_bank_w),
    .read_col_i(line_read_col_w),
    .column_o(line_column_w),
    .column_valid_o(line_column_valid_w)
);

tile_window_generator_3x3 #(
    .DATA_WIDTH(DATA_WIDTH),
    .TILE_WIDTH(TILE_WIDTH),
    .COL_WIDTH(COL_WIDTH)
) u_window_generator (
    .clk(clk),
    .rst_n(rst_n),
    .start_row_i(window_start_row_w),
    .column_i(line_column_w),
    .column_valid_i(line_column_valid_w),
    .column_ready_o(window_column_ready_w),
    .window_o(input_window_w),
    .window_col_o(),
    .window_last_o(),
    .window_valid_o(window_valid_w),
    .window_ready_i(window_ready_w)
);

tile_conv_controller #(
    .TILE_WIDTH(TILE_WIDTH),
    .TILE_HEIGHT(TILE_HEIGHT),
    .OUTPUT_WIDTH(OUTPUT_WIDTH),
    .OUTPUT_HEIGHT(OUTPUT_HEIGHT),
    .COL_WIDTH(COL_WIDTH),
    .OUTPUT_SIZE(OUTPUT_SIZE),
    .OUTPUT_ADDR_WIDTH(OUTPUT_ADDR_WIDTH)
) u_controller (
    .clk(clk),
    .rst_n(rst_n),
    .start_i(start_i),
    .loader_row_done_i(loader_row_done_w),
    .column_ready_i(window_column_ready_w),
    .column_valid_i(line_column_valid_w),
    .window_valid_i(window_valid_w),
    .result_valid_i(result_valid_o),
    .result_ready_i(result_ready_i),
    .loader_start_o(loader_start_w),
    .loader_enable_o(loader_enable_w),
    .line_read_en_o(line_read_en_w),
    .line_top_bank_o(line_top_bank_w),
    .line_read_col_o(line_read_col_w),
    .window_start_row_o(window_start_row_w),
    .window_ready_o(window_ready_w),
    .acc_load_bias_o(acc_load_bias_w),
    .mac_en_o(mac_en_w),
    .mac_last_o(mac_last_w),
    .output_addr_o(issue_output_addr_w),
    .busy_o(busy_o),
    .done_o(done_o),
    .state_o(state_o)
);

conv_weight_mem #(
    .DATA_WIDTH(DATA_WIDTH),
    .IC(1),
    .OC(1),
    .K_H(3),
    .K_W(3),
    .WEIGHT_SIZE(9),
    .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
) u_weight_mem (
    .clk(clk),
    .rst_n(rst_n),
    .write_en_i(weight_load_en_i),
    .write_addr_i(weight_load_addr_i),
    .write_data_i(weight_load_data_i),
    .window_base_addr_i({WEIGHT_ADDR_WIDTH{1'b0}}),
    .window_o(weight_window_w)
);

conv_bias_mem #(
    .ACC_WIDTH(ACC_WIDTH),
    .OC(1),
    .BIAS_SIZE(1),
    .BIAS_ADDR_WIDTH(1)
) u_bias_mem (
    .clk(clk),
    .rst_n(rst_n),
    .write_en_i(bias_load_en_i),
    .write_addr_i(1'b0),
    .write_data_i(bias_load_data_i),
    .read_addr_i(1'b0),
    .read_data_o(bias_data_w)
);

conv_datapath #(
    .DATA_WIDTH(DATA_WIDTH),
    .MUL_WIDTH(MUL_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .K_H(3),
    .K_W(3),
    .OUTPUT_ADDR_WIDTH(OUTPUT_ADDR_WIDTH),
    .ACC_BANK_SIZE(1),
    .ENABLE_ACTIVATION(0)
) u_datapath (
    .clk(clk),
    .rst_n(rst_n),
    .acc_load_bias_i(acc_load_bias_w),
    .mac_en_i(mac_en_w),
    .mac_last_i(mac_last_w),
    .output_addr_i(issue_output_addr_w),
    .result_ready_i(result_ready_i),
    .input_window_i(input_window_w),
    .weight_window_i(weight_window_w),
    .bias_i(bias_data_w),
    .acc_o(),
    .result_valid_o(result_valid_o),
    .result_addr_o(result_addr_o),
    .result_o(result_data_o),
    .busy_o()
);

assign result_last_o = result_addr_o == OUTPUT_SIZE - 1;

endmodule
