`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/07/29 16:39:18
// Design Name: 
// Module Name: conv_RGB
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module PE #(  // 3x3x3 conv op
    CONV_SIZE = 3 * 3,
    INPUT_CHANNEL = 3,
    NUM_OF_FILTERS = 16
)
(
    input   wire                        clk_i,
    input   wire                        rst_n,

    input   wire    [27 * 8 - 1:0]      in_a,     // 3x3  moving, (before rgb_data_i)
    input   wire    [27 * 8 - 1:0]      in_b,   // 3x3  fixed (before rgb_weight_i)

    output  reg     [27 * 8 - 1:0]      out_a,
    output  reg     [7:0]              out_c
);

    wire    [71:0]  r_data_i;     // 3x3 size with 8bit per 1 size
    wire    [71:0]  g_data_i;
    wire    [71:0]  b_data_i;

    wire    [71:0]  r_weight_i;
    wire    [71:0]  g_weight_i;
    wire    [71:0]  b_weight_i;

    wire    [7:0]  r_data_o;
    wire    [7:0]  g_data_o;
    wire    [7:0]  b_data_o;

    assign  r_data_i = in_a[215:144];
    assign  g_data_i = in_a[143:72];
    assign  b_data_i = in_a[71:0];

    assign  r_weight_i = in_b[215:144];
    assign  g_weight_i = in_b[143:72];
    assign  b_weight_i = in_b[71:0];

    always @(posedge clk_i) begin
        if (!rst_n) begin
            out_a <= 0;
            out_c <= 0;
        end
        else begin
            out_c <= r_data_o + g_data_o + b_data_o;
            out_a <= in_a;
        end
    end

    conv conv_r_channel (
        .clk_i      (clk_i),
        .rst_n      (rst_n),

        .k_0        (r_data_i[71:64]),
        .k_1        (r_data_i[63:56]),
        .k_2        (r_data_i[55:48]),
        .k_3        (r_data_i[47:40]),
        .k_4        (r_data_i[39:32]),
        .k_5        (r_data_i[31:24]),
        .k_6        (r_data_i[23:16]),
        .k_7        (r_data_i[15:8]),
        .k_8        (r_data_i[7:0]),

        .w_0        (r_weight_i[71:64]),
        .w_1        (r_weight_i[63:56]),
        .w_2        (r_weight_i[55:48]),
        .w_3        (r_weight_i[47:40]),
        .w_4        (r_weight_i[39:32]),
        .w_5        (r_weight_i[31:24]),
        .w_6        (r_weight_i[23:16]),
        .w_7        (r_weight_i[15:8]),
        .w_8        (r_weight_i[7:0]),

        .r_o        (r_data_o)
    );

    conv conv_g_channel (
        .clk_i      (clk_i),
        .rst_n      (rst_n),

        .k_0        (g_data_i[71:64]),
        .k_1        (g_data_i[63:56]),
        .k_2        (g_data_i[55:48]),
        .k_3        (g_data_i[47:40]),
        .k_4        (g_data_i[39:32]),
        .k_5        (g_data_i[31:24]),
        .k_6        (g_data_i[23:16]),
        .k_7        (g_data_i[15:8]),
        .k_8        (g_data_i[7:0]),

        .w_0        (g_weight_i[71:64]),
        .w_1        (g_weight_i[63:56]),
        .w_2        (g_weight_i[55:48]),
        .w_3        (g_weight_i[47:40]),
        .w_4        (g_weight_i[39:32]),
        .w_5        (g_weight_i[31:24]),
        .w_6        (g_weight_i[23:16]),
        .w_7        (g_weight_i[15:8]),
        .w_8        (g_weight_i[7:0]),

        .r_o        (g_data_o)
    );

    conv conv_b_channel (
        .clk_i      (clk_i),
        .rst_n      (rst_n),

        .k_0        (b_data_i[71:64]),
        .k_1        (b_data_i[63:56]),
        .k_2        (b_data_i[55:48]),
        .k_3        (b_data_i[47:40]),
        .k_4        (b_data_i[39:32]),
        .k_5        (b_data_i[31:24]),
        .k_6        (b_data_i[23:16]),
        .k_7        (b_data_i[15:8]),
        .k_8        (b_data_i[7:0]),

        .w_0        (b_weight_i[71:64]),
        .w_1        (b_weight_i[63:56]),
        .w_2        (b_weight_i[55:48]),
        .w_3        (b_weight_i[47:40]),
        .w_4        (b_weight_i[39:32]),
        .w_5        (b_weight_i[31:24]),
        .w_6        (b_weight_i[23:16]),
        .w_7        (b_weight_i[15:8]),
        .w_8        (b_weight_i[7:0]),

        .r_o        (b_data_o)
    );
endmodule
