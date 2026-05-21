`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/08/26 22:13:17
// Design Name: 
// Module Name: padding_top
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


module padding_top (
                input clk,
                input reset,
                input en,
                input wait_en,

                input [8:0] count,
                input imgDataValid,

                output intr,

                input [3327:0] R_input,
                input [3327:0] G_input,
                input [3327:0] B_input,

                output [3343:0] R_row0, //418x8=3344
                output [3343:0] G_row0,
                output [3343:0] B_row0,
                 
                output [3343:0] R_row1, //418x8=3344
                output [3343:0] G_row1,
                output [3343:0] B_row1,
                
                output [3343:0] R_row2, //418x8=3344
                output [3343:0] G_row2,
                output [3343:0] B_row2

);



    
wire [3343:0] R_padded;
wire [3343:0] G_padded;
wire [3343:0] B_padded;





padding padding(
                .clk(clk),
                .reset(reset),
                .en(en),
                .count(count),
                .R_input(R_input),
                .G_input(G_input),
                .B_input(B_input),
                .R_padded(R_padded),
                .G_padded(G_padded),
                .B_padded(B_padded)

);
 
padding_reg padding_reg (
                .clk(clk),
                .reset(reset),
                .en(en),
                .wait_en(wait_en),
                .imgDataValid(imgDataValid),

                .intr(intr),
                


                .R_padded(R_padded),
                .G_padded(G_padded),
                .B_padded(B_padded),

                .R_row0(R_row0), //418x8=3344
                .G_row0(G_row0),
                .B_row0(B_row0),
                 
                .R_row1(R_row1), //418x8=3344
                .G_row1(G_row1),
                .B_row1(B_row1),
                
                .R_row2(R_row2), //418x8=3344
                .G_row2(G_row2),
                .B_row2(B_row2)

);
   

endmodule