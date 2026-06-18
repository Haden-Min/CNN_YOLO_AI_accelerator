`timescale 1ns/1ps

module weight_buffer_9 #(
    parameter DATA_WIDTH = 8,
    parameter K_H        = 3,
    parameter K_W        = 3,
    parameter ADDR_WIDTH = 4
)(
    input wire clk,
    input wire rst_n,

    input wire write_en_i,
    input wire [ADDR_WIDTH-1:0] write_addr_i,
    input wire signed [DATA_WIDTH-1:0] data_i,

    output wire signed [K_H*K_W*DATA_WIDTH-1:0] weight_o
);

localparam WEIGHT_SIZE = K_H * K_W;

reg signed [DATA_WIDTH-1:0] weight_mem_r [0:WEIGHT_SIZE-1];

integer i;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < WEIGHT_SIZE; i = i + 1) begin
            weight_mem_r[i] <= {DATA_WIDTH{1'b0}};
        end
    end
    else if (write_en_i) begin
        weight_mem_r[write_addr_i] <= data_i;
    end
end

genvar lane;
generate
    for (lane = 0; lane < WEIGHT_SIZE; lane = lane + 1) begin : gen_weight_out
        assign weight_o[(lane+1)*DATA_WIDTH-1:lane*DATA_WIDTH] = weight_mem_r[lane];
    end
endgenerate

endmodule
