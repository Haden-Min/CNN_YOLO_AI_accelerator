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
    reg padding_en;
    reg imgDataValid;

    reg [7:0] R_input;
    reg [7:0] G_input;
    reg [7:0] B_input;

    wire intr;

    wire [3343:0] R_row0; //418x8=3344
    wire [3343:0] G_row0;
    wire [3343:0] B_row0;
    wire [3343:0] R_row1; //418x8=3344
    wire [3343:0] G_row1;
    wire [3343:0] B_row1;
    wire [3343:0] R_row2; //418x8=3344
    wire [3343:0] G_row2;
    wire [3343:0] B_row2;
    
    padding padding(
                .clk(clk),
                .reset(reset),
                .padding_en(padding_en),
                .imgDataValid(imgDataValid),

                .R_input(R_input),
                .G_input(G_input),
                .B_input(B_input),

                .intr(intr),

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
        padding_en = 0;
        reset = 1; 
        imgDataValid = 1;
        #10

        reset = 0; 
        #5
        R_input = 8'd1; //
        G_input = 8'd1;
        B_input = 8'd1;
        padding_en = 1;
   
        #10
        R_input = 8'd1; //
        G_input = 8'd1;
        B_input = 8'd1;

        #10
        R_input = 8'd1; //
        G_input = 8'd1;
        B_input = 8'd1;
    
        #10
        R_input = 8'd1; //0000_1111_0000
        G_input = 8'd1;
        B_input = 8'd1;

        #10
        R_input = 8'd1; //0000_1111_0000
        G_input = 8'd1;
        B_input = 8'd1;
        //wait_en = 1;


        #10
        R_input = 8'd1; //0000_1111_0000
        G_input = 8'd1;
        B_input = 8'd1;

        #10
        R_input = 8'd1; //0000_1111_0000
        G_input = 8'd1;
        B_input = 8'd1;


    end

    // Clock generation
    always #5 clk = ~clk; // 10ns clock period (100 MHz)

endmodule