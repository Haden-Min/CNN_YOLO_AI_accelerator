`timescale 1ns/1ps

module conv_output_mem #(
    parameter ACC_WIDTH = 32,
    parameter OC      = 1,
    parameter OUT_H   = 3,
    parameter OUT_W   = 3,

    parameter OUTPUT_SIZE = OC * OUT_H * OUT_W,
    parameter OUTPUT_ADDR_WIDTH = (OUTPUT_SIZE <= 1) ? 1 : $clog2(OUTPUT_SIZE)
)(
    input wire clk,
    input wire rst_n,

    input wire write_en_i,
    input wire [OUTPUT_ADDR_WIDTH-1:0] write_addr_i,
    input wire signed [ACC_WIDTH-1:0] write_data_i,

    input wire [OUTPUT_ADDR_WIDTH-1:0] read_addr_i,

    output wire signed [ACC_WIDTH-1:0] read_data_o
);

(* ram_style = "block" *) reg signed [ACC_WIDTH-1:0] mem_r [0:OUTPUT_SIZE-1];
reg signed [ACC_WIDTH-1:0] read_data_r;

always @(posedge clk) begin
    if (write_en_i) begin
        mem_r[write_addr_i] <= write_data_i;
    end

    read_data_r <= mem_r[read_addr_i];
end

assign read_data_o = read_data_r;

endmodule
