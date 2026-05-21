`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/08/26 22:14:06
// Design Name: 
// Module Name: padding_reg
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

// fsm
module padding_reg (
    input clk,
    input reset,
    input en,

    input [3343:0] R_padded,
    input [3343:0] G_padded,
    input [3343:0] B_padded,

    output reg [3343:0] R_row0, //418x8=3344
    output reg [3343:0] G_row0,
    output reg [3343:0] B_row0,
     
    output reg [3343:0] R_row1, //418x8=3344
    output reg [3343:0] G_row1,
    output reg [3343:0] B_row1,
    
    output reg [3343:0] R_row2, //418x8=3344
    output reg [3343:0] G_row2,
    output reg [3343:0] B_row2,
    output reg [8:0] count
);

reg [2:0] present_state, next_state;
reg [1:0] ctrl, wait_a;

localparam IDLE = 3'd0;
localparam S1   = 3'd1;
localparam S2   = 3'd2;
localparam S3   = 3'd3;
localparam WAIT = 3'd4;

always @(posedge clk) begin 
    if(reset) begin
        present_state <= IDLE;
        wait_a <= 0;  // Reset `wait_a` on reset
    end
    else begin
        present_state <= next_state;
        
    end
end

always @(*) begin
    case (present_state)
        IDLE: begin
            if (en) begin
                next_state = WAIT;
            end else begin
                next_state = IDLE;
            end
        end
        S1: begin
            if (ctrl == 1) begin
                next_state = S2;
            end else begin
                next_state = S1;
            end
        end
        S2: begin
            if (ctrl == 2) begin
                next_state = S3;
            end else begin
                next_state = S2;
            end
        end
        S3: begin
            if (ctrl == 3) begin
                next_state = WAIT; // Return to WAIT state after completing S3
            end else begin
                next_state = S3;
            end
        end
        WAIT: begin
            if(wait_a == 2'd2)
                next_state = S1;  // Move to S1 after wait period
            else
                next_state = WAIT;  // Stay in WAIT state
        end
        default: begin
            next_state = IDLE;
        end
    endcase
end

always @(posedge clk) begin
    case(present_state)
        IDLE: begin
            R_row0 <= 3343'dz;
            G_row0 <= 3343'dz;
            B_row0 <= 3343'dz;
            R_row1 <= 3343'dz;
            G_row1 <= 3343'dz;
            B_row1 <= 3343'dz;
            R_row2 <= 3343'dz;
            G_row2 <= 3343'dz;
            B_row2 <= 3343'dz;

            count  <= 0;
            ctrl   <= 2'd1;
        end
        
        S1: begin
            R_row0 <= R_padded;
            G_row0 <= G_padded;
            B_row0 <= B_padded;
            
            if (count == 9'd416)
                count <= 0;
            count <= count + 1;
            ctrl   <= 2'd2;
        end

        S2: begin
            R_row1 <= R_padded;
            G_row1 <= G_padded;
            B_row1 <= B_padded;

            if (count == 9'd416)
                count <= 0;
            count <= count + 1;
            ctrl   <= 2'd3;
        end
        
        S3: begin
            R_row2 <= R_padded;
            G_row2 <= G_padded;
            B_row2 <= B_padded;

            if (count == 9'd416)
                count <= 0;
            count <= count + 1;
            ctrl   <= 2'd1;
            wait_a <= 0;
        end

        WAIT: begin
            
            wait_a <= wait_a + 1'b1  ;
            
            if (count == 9'd416)
                count <= 0;
            count <= count + 1;


        end
    endcase
end

endmodule
