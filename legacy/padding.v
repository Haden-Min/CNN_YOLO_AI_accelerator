`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/08/26 22:15:04
// Design Name: 
// Module Name: padding
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


module padding (
                input clk,
                input reset,
                input en,
                input [8:0] count,


                input [3327:0] R_input,
                input [3327:0] G_input,
                input [3327:0] B_input,

                output reg [3343:0] R_padded,
                output reg [3343:0] G_padded,
                output reg [3343:0] B_padded



);



always @(posedge clk) begin // for reset
    if(reset) begin
        R_padded <= 0;
        G_padded <= 0;
        B_padded <= 0;

	end
	else begin
        if(en)
        begin
            if(count==9'd0 || count==9'd415)
            begin
                R_padded <= 0;
                G_padded <= 0;
                B_padded <= 0;
            end
            else
            begin
                R_padded <= {8'b0, R_input, 8'b0};
                G_padded <= {8'b0, G_input, 8'b0};
                B_padded <= {8'b0, B_input, 8'b0};
            end
        end
    end
end
    
endmodule


