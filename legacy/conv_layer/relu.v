`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/08/12 15:52:52
// Design Name: 
// Module Name: relu
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


module relu ( a, b_o);


input signed [63:0] a;

output signed [7:0] b_o;

wire   [63:0]   b;
assign b = (a<=0) ? 0 : a;
assign b_o = {b[63],b[6:0]};

endmodule
