`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/08/26 22:39:02
// Design Name: 
// Module Name: tb_padding_top
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


`timescale 1ns/1ps

module tb_padding_top ();

    reg clk;
    reg reset;
    reg en;

    reg [3327:0] R_input;
    reg [3327:0] G_input;
    reg [3327:0] B_input;
    
    wire [3343:0] R_row0; //418x8=3344
    wire [3343:0] G_row0;
    wire [3343:0] B_row0;

    wire [3343:0] R_row1; //418x8=3344
    wire [3343:0] G_row1;
    wire [3343:0] B_row1;

    wire [3343:0] R_row2; //418x8=3344
    wire [3343:0] G_row2;
    wire [3343:0] B_row2;



    padding_top padding_top(
                .clk(clk),
                .reset(reset),
                .en(en),

                .R_input(R_input),
                .G_input(G_input),
                .B_input(B_input),

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





    initial begin

        clk = 0;
        reset = 0;
        en = 0;

        
        reset = 1; #10
        reset = 0; 

        R_input = 3328'd1; //
        G_input = 3328'd1;
        B_input = 3328'd1;
        
        #15
        
        en = 1;

        
        R_input = 3328'd1; //
        G_input = 3328'd1;
        B_input = 3328'd1;

        #10
                
        R_input = 3328'd2; //0000_1111
        G_input = 3328'd2;
        B_input = 3328'd2;
    
        #10

        R_input = 3328'd3; //0000_1111_0000
        G_input = 3328'd3;
        B_input = 3328'd3;

        #10
        R_input = 3328'd7; //0000_1111_0000
        G_input = 3328'd7;
        B_input = 3328'd7;

        #10

        R_input = 3328'd240; //0000_1111_0000
        G_input = 3328'd240;
        B_input = 3328'd240;

        #10
        R_input = 3328'd7; //0000_1111_0000
        G_input = 3328'd7;
        B_input = 3328'd7;


    end

    // Clock generation
    always #5 clk = ~clk; // 10ns clock period (100 MHz)

endmodule