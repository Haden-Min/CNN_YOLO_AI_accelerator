module top_single_conv #(
    parameter DATA_WIDTH = 8,
    parameter MUL_WIDTH  = 16,
    parameter ACC_WIDTH  = 32,

    parameter INPUT_W  = 5,
    parameter INPUT_H  = 5,
    parameter KERNEL   = 3,
    parameter OUTPUT_W = 3,
    parameter OUTPUT_H = 3,

    parameter INPUT_ADDR_WIDTH  = 5,
    parameter WEIGHT_ADDR_WIDTH = 4,
    parameter OUTPUT_ADDR_WIDTH = 4,

    parameter OUT_POS_WIDTH = 2,
    parameter K_POS_WIDTH   = 2
)(
    input wire clk,
    input wire rst_n,
    input wire start_i,

    input wire signed [DATA_WIDTH-1:0] input_data_i,
    input wire signed [DATA_WIDTH-1:0] weight_data_i,
    input wire signed [ACC_WIDTH-1:0]  bias_data_i,

    output wire [INPUT_ADDR_WIDTH-1:0]  input_addr_o,
    output wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr_o,
    output wire [OUTPUT_ADDR_WIDTH-1:0] output_addr_o,

    output wire output_we_o,

    output wire busy_o,
    output wire done_o,

    output wire signed [ACC_WIDTH-1:0] output_data_o
);

wire acc_clear_w;
wire acc_load_bias_w;
wire mac_en_w;

single_conv_control #(
    .INPUT_W(INPUT_W),
    .INPUT_H(INPUT_H),
    .KERNEL(KERNEL),
    .OUTPUT_W(OUTPUT_W),
    .OUTPUT_H(OUTPUT_H),

    .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH),
    .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
    .OUTPUT_ADDR_WIDTH(OUTPUT_ADDR_WIDTH),

    .OUT_POS_WIDTH(OUT_POS_WIDTH),
    .K_POS_WIDTH(K_POS_WIDTH)
) u_control (
    .clk(clk),
    .rst_n(rst_n),
    .start_i(start_i),

    .busy_o(busy_o),
    .done_o(done_o),

    .acc_clear_o(acc_clear_w),
    .acc_load_bias_o(acc_load_bias_w),
    .mac_en_o(mac_en_w),
    .output_we_o(output_we_o),

    .input_addr_o(input_addr_o),
    .weight_addr_o(weight_addr_o),
    .output_addr_o(output_addr_o)
);

single_conv_datapath #(
    .DATA_WIDTH(DATA_WIDTH),
    .MUL_WIDTH(MUL_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
) u_datapath (
    .clk(clk),
    .rst_n(rst_n),

    .acc_clear_i(acc_clear_w),
    .acc_load_bias_i(acc_load_bias_w),
    .mac_en_i(mac_en_w),

    .input_data_i(input_data_i),
    .weight_data_i(weight_data_i),
    .bias_data_i(bias_data_i),

    .acc_o(output_data_o)
);

endmodule