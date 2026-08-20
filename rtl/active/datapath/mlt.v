`timescale 1ns/1ps

module mlt #(
    parameter DATA_WIDTH=8
)
 (  //input wire clk,
    //input wire en,
    
    input wire signed [DATA_WIDTH-1:0] data_i,
    input wire signed [DATA_WIDTH-1:0] kernel_i,

    output wire signed [2*DATA_WIDTH-1:0] mul_o
    // output reg busy,
    // output reg done
);

    // always @(posedge clk) begin
    //     if(en)
    //         mul_o<=data_i*kernel_i;
    // end 

    assign mul_o = data_i * kernel_i; //조합회로로 구성



endmodule
