module single_conv_datapath #(
    parameter DATA_WIDTH = 8,
    parameter MUL_WIDTH  = 16,
    parameter ACC_WIDTH  = 32
)(
    input wire clk,
    input wire rst_n,

    input wire acc_clear_i,
    input wire acc_load_bias_i,
    input wire mac_en_i,

    input wire signed [DATA_WIDTH-1:0] input_data_i,
    input wire signed [DATA_WIDTH-1:0] weight_data_i,
    input wire signed [ACC_WIDTH-1:0]  bias_data_i,

    output wire signed [ACC_WIDTH-1:0] acc_o
);

wire signed [MUL_WIDTH-1:0] mul_w;

mlt #(
    .DATA_WIDTH(DATA_WIDTH)
) u_mlt (
    .data_i(input_data_i),
    .kernel_i(weight_data_i),
    .mul_o(mul_w)
);

acc #(
    .IN_WIDTH(MUL_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
) u_acc (
    .clk(clk),
    .rst_n(rst_n),

    .clear_i(acc_clear_i),
    .load_bias_i(acc_load_bias_i),
    .en_i(mac_en_i),

    .data_i(mul_w),
    .bias_i(bias_data_i),

    .acc_o(acc_o)
);

endmodule