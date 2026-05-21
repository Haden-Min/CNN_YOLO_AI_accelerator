`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/08/12 17:33:03
// Design Name: 
// Module Name: sys_array
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


module sys_array #(
    CONV_SIZE = 3 * 3,
    INPUT_CHANNEL = 3,
    NUM_OF_FILTERS = 16,

    parameter K0  = 72'h0,
    parameter K1  = 72'h0,
    parameter K2  = 72'h0,
    parameter K3  = 72'h0,
    parameter K4  = 72'h0,
    parameter K5  = 72'h0,
    parameter K6  = 72'h0,
    parameter K7  = 72'h0,
    parameter K8  = 72'h0,
    parameter K9  = 72'h0,
    parameter K10 = 72'h0,
    parameter K11 = 72'h0,
    parameter K12 = 72'h0,
    parameter K13 = 72'h0,
    parameter K14 = 72'h0,
    parameter K15 = 72'h0
)(
    input   wire                    clk_i,
    input   wire                    rst_n,
    input   wire  [27 * 8 - 1:0]    a0,

    output  wire  [7:0]            c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15,
    output  reg                    valid_o
    );

    wire   [27 * 8 - 1:0]   a01, a12, a23, a34, a45, a56, a67, a78, a89, a910, a1011, a1112, a1213, a1314, a1415;

    PE PE0  (.clk_i (clk_i), .rst_n (rst_n), .in_a (a0),    .in_b (K0),  .out_a (a01),   .out_c (c0) );
    PE PE1  (.clk_i (clk_i), .rst_n (rst_n), .in_a (a01),   .in_b (K1),  .out_a (a12),   .out_c (c1) );
    PE PE2  (.clk_i (clk_i), .rst_n (rst_n), .in_a (a12),   .in_b (K2),  .out_a (a23),   .out_c (c2) );
    PE PE3  (.clk_i (clk_i), .rst_n (rst_n), .in_a (a23),   .in_b (K3),  .out_a (a34),   .out_c (c3) );
    PE PE4  (.clk_i (clk_i), .rst_n (rst_n), .in_a (a34),   .in_b (K4),  .out_a (a45),   .out_c (c4) );
    PE PE5  (.clk_i (clk_i), .rst_n (rst_n), .in_a (a45),   .in_b (K5),  .out_a (a56),   .out_c (c5) );
    PE PE6  (.clk_i (clk_i), .rst_n (rst_n), .in_a (a56),   .in_b (K6),  .out_a (a67),   .out_c (c6) );
    PE PE7  (.clk_i (clk_i), .rst_n (rst_n), .in_a (a67),   .in_b (K7),  .out_a (a78),   .out_c (c7) );
    PE PE8  (.clk_i (clk_i), .rst_n (rst_n), .in_a (a78),   .in_b (K8),  .out_a (a89),   .out_c (c8) );
    PE PE9  (.clk_i (clk_i), .rst_n (rst_n), .in_a (a89),   .in_b (K9),  .out_a (a910),  .out_c (c9) );
    PE PE10 (.clk_i (clk_i), .rst_n (rst_n), .in_a (a910),  .in_b (K10), .out_a (a1011), .out_c (c10));
    PE PE11 (.clk_i (clk_i), .rst_n (rst_n), .in_a (a1011), .in_b (K11), .out_a (a1112), .out_c (c11));
    PE PE12 (.clk_i (clk_i), .rst_n (rst_n), .in_a (a1112), .in_b (K12), .out_a (a1213), .out_c (c12));
    PE PE13 (.clk_i (clk_i), .rst_n (rst_n), .in_a (a1213), .in_b (K13), .out_a (a1314), .out_c (c13));
    PE PE14 (.clk_i (clk_i), .rst_n (rst_n), .in_a (a1314), .in_b (K14), .out_a (a1415), .out_c (c14));
    PE PE15 (.clk_i (clk_i), .rst_n (rst_n), .in_a (a1415), .in_b (K15), .out_a (),      .out_c (c15));
    
    always@ (posedge clk_i) begin
        if (!rst_n) begin
            valid_o <= 0;
        end
        else if (c15) begin
            valid_o <= 1;
        end
        else begin
            valid_o <= 0;
        end
    end
endmodule
