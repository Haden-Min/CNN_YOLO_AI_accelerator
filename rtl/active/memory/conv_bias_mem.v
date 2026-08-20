`timescale 1ns/1ps

module conv_bias_mem #(
    parameter ACC_WIDTH = 32,
    parameter OC = 1,

    parameter BIAS_SIZE = OC,
    parameter BIAS_ADDR_WIDTH = (BIAS_SIZE <= 1) ? 1 : $clog2(BIAS_SIZE)
)(
    input wire clk,
    input wire rst_n,

    input wire write_en_i,
    input wire [BIAS_ADDR_WIDTH-1:0] write_addr_i,
    input wire signed [ACC_WIDTH-1:0] write_data_i,

    input wire [BIAS_ADDR_WIDTH-1:0] read_addr_i,

    output wire signed [ACC_WIDTH-1:0] read_data_o
);

(* ram_style = "block" *) reg signed [ACC_WIDTH-1:0] mem_r [0:BIAS_SIZE-1];
reg signed [ACC_WIDTH-1:0] read_data_r;

always @(posedge clk) begin
    if (write_en_i) begin
        mem_r[write_addr_i] <= write_data_i;
    end

    read_data_r <= mem_r[read_addr_i];
end

assign read_data_o = read_data_r;

endmodule
