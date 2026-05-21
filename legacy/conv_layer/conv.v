


`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/07/25 12:09:25
// Design Name: 
// Module Name: conv
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

// IO 문제 발생
module conv(                                           
    input   wire                            clk_i,
    input   wire                            rst_n,

    input   wire    signed      [7:0]       k_0,
    input   wire    signed      [7:0]       k_1,
    input   wire    signed      [7:0]       k_2,
    input   wire    signed      [7:0]       k_3,
    input   wire    signed      [7:0]       k_4,
    input   wire    signed      [7:0]       k_5,
    input   wire    signed      [7:0]       k_6,
    input   wire    signed      [7:0]       k_7,
    input   wire    signed      [7:0]       k_8,

    input   wire    signed      [7:0]       w_0,
    input   wire    signed      [7:0]       w_1,
    input   wire    signed      [7:0]       w_2,
    input   wire    signed      [7:0]       w_3,
    input   wire    signed      [7:0]       w_4,
    input   wire    signed      [7:0]       w_5,
    input   wire    signed      [7:0]       w_6,
    input   wire    signed      [7:0]       w_7,
    input   wire    signed      [7:0]       w_8,

    output  wire    signed      [7:0]      r_o
    );

    wire    signed  [15:0]      t [8:0];

    reg     signed  [63:0]      r;

    booth_multiplier mul_t0  (
        .M      (k_0),
        .Q      (w_0),
        .result      (t[0])
    );

    booth_multiplier mul_t1  (
        .M      (k_1),
        .Q      (w_1),
        .result      (t[1])
    );

    booth_multiplier mul_t2  (
        .M      (k_2),
        .Q      (w_2),
        .result      (t[2])
    );

    booth_multiplier mul_t3  (
        .M      (k_3),
        .Q      (w_3),
        .result      (t[3])
    );

    booth_multiplier mul_t4  (
        .M      (k_4),
        .Q      (w_4),
        .result      (t[4])
    );

    booth_multiplier mul_t5  (
        .M      (k_5),
        .Q      (w_5),
        .result      (t[5])
    );

    booth_multiplier mul_t6  (
        .M      (k_6),
        .Q      (w_6),
        .result      (t[6])
    );

    booth_multiplier mul_t7  (
        .M      (k_7),
        .Q      (w_7),
        .result      (t[7])
    );

    booth_multiplier mul_t8  (
        .M     (k_8),
        .Q      (w_8),
        .result      (t[8])
    );

    always @(posedge clk_i) begin
        if (!rst_n) begin
            r <= 0;
        end
        else begin
            r <= t[0] + t[1] + t[2] + t[3] + t[4] + t[5] + t[6] + t[7] + t[8];
        end
    end

    relu relu_dut (
        .a      (r),
        .b_o      (r_o)
    );
    
endmodule
