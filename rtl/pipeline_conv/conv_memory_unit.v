`timescale 1ns/1ps

module conv_memory_unit #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32,

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
    parameter OUTPUT_ADDR_WIDTH = (OUTPUT_SIZE <= 1) ? 1 : $clog2(OUTPUT_SIZE)
)(
    input wire clk,
    input wire rst_n,

    input wire input_load_en_i,
    input wire [INPUT_ADDR_WIDTH-1:0] input_load_addr_i,
    input wire signed [DATA_WIDTH-1:0] input_load_data_i,

    input wire weight_load_en_i,
    input wire [WEIGHT_ADDR_WIDTH-1:0] weight_load_addr_i,
    input wire signed [DATA_WIDTH-1:0] weight_load_data_i,

    input wire bias_load_en_i,
    input wire [BIAS_ADDR_WIDTH-1:0] bias_load_addr_i,
    input wire signed [ACC_WIDTH-1:0] bias_load_data_i,

    input wire [INPUT_ADDR_WIDTH-1:0] input_base_addr_i,
    input wire input_window_req_i,
    input wire [WEIGHT_ADDR_WIDTH-1:0] weight_base_addr_i,
    input wire [BIAS_ADDR_WIDTH-1:0] bias_read_addr_i,

    input wire output_write_en_i,
    input wire [OUTPUT_ADDR_WIDTH-1:0] output_write_addr_i,
    input wire signed [ACC_WIDTH-1:0] output_write_data_i,
    input wire [OUTPUT_ADDR_WIDTH-1:0] output_read_addr_i,

    output wire signed [K_H*K_W*DATA_WIDTH-1:0] input_window_o,
    output wire input_window_valid_o,
    output wire signed [K_H*K_W*DATA_WIDTH-1:0] weight_window_o,
    output wire signed [ACC_WIDTH-1:0] bias_data_o,
    output wire signed [ACC_WIDTH-1:0] output_read_data_o
);

conv_input_mem #(
    .DATA_WIDTH(DATA_WIDTH),
    .IC(IC),
    .IN_H(IN_H),
    .IN_W(IN_W),
    .K_H(K_H),
    .K_W(K_W),
    .STRIDE(STRIDE),
    .INPUT_SIZE(INPUT_SIZE),
    .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH)
) u_input_mem (
    .clk(clk),
    .rst_n(rst_n),
    .write_en_i(input_load_en_i),
    .write_addr_i(input_load_addr_i),
    .write_data_i(input_load_data_i),
    .window_base_addr_i(input_base_addr_i),
    .window_req_i(input_window_req_i),
    .window_o(input_window_o),
    .window_valid_o(input_window_valid_o)
);

conv_weight_mem #(
    .DATA_WIDTH(DATA_WIDTH),
    .IC(IC),
    .OC(OC),
    .K_H(K_H),
    .K_W(K_W),
    .WEIGHT_SIZE(WEIGHT_SIZE),
    .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
) u_weight_mem (
    .clk(clk),
    .rst_n(rst_n),
    .write_en_i(weight_load_en_i),
    .write_addr_i(weight_load_addr_i),
    .write_data_i(weight_load_data_i),
    .window_base_addr_i(weight_base_addr_i),
    .window_o(weight_window_o)
);

conv_bias_mem #(
    .ACC_WIDTH(ACC_WIDTH),
    .OC(OC),
    .BIAS_SIZE(BIAS_SIZE),
    .BIAS_ADDR_WIDTH(BIAS_ADDR_WIDTH)
) u_bias_mem (
    .clk(clk),
    .rst_n(rst_n),
    .write_en_i(bias_load_en_i),
    .write_addr_i(bias_load_addr_i),
    .write_data_i(bias_load_data_i),
    .read_addr_i(bias_read_addr_i),
    .read_data_o(bias_data_o)
);

generate
    if (ENABLE_OUTPUT_BUFFER) begin : gen_output_buffer
        conv_output_mem #(
            .ACC_WIDTH(ACC_WIDTH),
            .OC(OC),
            .OUT_H(OUT_H),
            .OUT_W(OUT_W),
            .OUTPUT_SIZE(OUTPUT_SIZE),
            .OUTPUT_ADDR_WIDTH(OUTPUT_ADDR_WIDTH)
        ) u_output_mem (
            .clk(clk),
            .rst_n(rst_n),
            .write_en_i(output_write_en_i),
            .write_addr_i(output_write_addr_i),
            .write_data_i(output_write_data_i),
            .read_addr_i(output_read_addr_i),
            .read_data_o(output_read_data_o)
        );
    end
    else begin : gen_no_output_buffer
        assign output_read_data_o = {ACC_WIDTH{1'b0}};
    end
endgenerate

endmodule
