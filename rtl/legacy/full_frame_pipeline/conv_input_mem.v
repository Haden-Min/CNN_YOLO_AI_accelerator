`timescale 1ns/1ps

module conv_input_mem #(
    parameter DATA_WIDTH = 8,
    parameter IC      = 1,
    parameter IN_H    = 5,
    parameter IN_W    = 5,
    parameter K_H     = 3,
    parameter K_W     = 3,
    parameter STRIDE  = 1,

    parameter INPUT_SIZE = IC * IN_H * IN_W,
    parameter INPUT_ADDR_WIDTH = (INPUT_SIZE <= 1) ? 1 : $clog2(INPUT_SIZE)
)(
    input wire clk,
    input wire rst_n,

    input wire write_en_i,
    input wire [INPUT_ADDR_WIDTH-1:0] write_addr_i,
    input wire signed [DATA_WIDTH-1:0] write_data_i,

    input wire [INPUT_ADDR_WIDTH-1:0] window_base_addr_i,
    input wire window_req_i,

    output wire signed [K_H*K_W*DATA_WIDTH-1:0] window_o,
    output wire window_valid_o
);

wire signed [K_H*K_W*DATA_WIDTH-1:0] full_window_w;
wire full_window_valid_w;
wire signed [K_H*K_W*DATA_WIDTH-1:0] append_window_w;
wire append_window_valid_w;

conv_input_line_buffer #(
    .DATA_WIDTH(DATA_WIDTH),
    .IC(IC),
    .IN_H(IN_H),
    .IN_W(IN_W),
    .K_H(K_H),
    .K_W(K_W),
    .STRIDE(STRIDE),
    .INPUT_SIZE(INPUT_SIZE),
    .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH)
) u_line_buffer (
    .clk(clk),
    .rst_n(rst_n),
    .write_en_i(write_en_i),
    .write_addr_i(write_addr_i),
    .write_data_i(write_data_i),
    .window_base_addr_i(window_base_addr_i),
    .full_window_o(full_window_w),
    .full_window_valid_o(full_window_valid_w),
    .append_window_o(append_window_w),
    .append_window_valid_o(append_window_valid_w)
);

conv_window_buffer #(
    .DATA_WIDTH(DATA_WIDTH),
    .IC(IC),
    .IN_H(IN_H),
    .IN_W(IN_W),
    .K_H(K_H),
    .K_W(K_W),
    .STRIDE(STRIDE),
    .INPUT_SIZE(INPUT_SIZE),
    .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH)
) u_window_buffer (
    .clk(clk),
    .rst_n(rst_n),
    .request_i(window_req_i),
    .window_base_addr_i(window_base_addr_i),
    .full_window_i(full_window_w),
    .full_window_valid_i(full_window_valid_w),
    .append_window_i(append_window_w),
    .append_window_valid_i(append_window_valid_w),
    .window_o(window_o),
    .window_ready_o(window_valid_o)
);

endmodule
