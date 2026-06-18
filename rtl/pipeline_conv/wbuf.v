`timescale 1ns/1ps

module wbuf #(
    parameter DATA_WIDTH = 8,
    parameter IN_H       = 5,
    parameter IN_W       = 5,
    parameter K_H        = 3,
    parameter K_W        = 3,
    parameter ADDR_WIDTH = 5,
    parameter OUT_H_WIDTH = 2,
    parameter OUT_W_WIDTH = 2
)(
    input wire clk,
    input wire rst_n,

    input wire write_en_i,
    input wire [ADDR_WIDTH-1:0] write_addr_i,
    input wire signed [DATA_WIDTH-1:0] data_i,

    input wire [OUT_H_WIDTH-1:0] window_oh_i,
    input wire [OUT_W_WIDTH-1:0] window_ow_i,

    output wire signed [K_H*K_W*DATA_WIDTH-1:0] window_o
);

localparam INPUT_SIZE = IN_H * IN_W;

reg signed [DATA_WIDTH-1:0] input_mem_r [0:INPUT_SIZE-1];

integer i;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < INPUT_SIZE; i = i + 1) begin
            input_mem_r[i] <= {DATA_WIDTH{1'b0}};
        end
    end
    else if (write_en_i) begin
        input_mem_r[write_addr_i] <= data_i;
    end
end

genvar kh;
genvar kw;
generate
    for (kh = 0; kh < K_H; kh = kh + 1) begin : gen_window_row
        for (kw = 0; kw < K_W; kw = kw + 1) begin : gen_window_col
            localparam integer LANE = kh * K_W + kw;
            assign window_o[(LANE+1)*DATA_WIDTH-1:LANE*DATA_WIDTH] =
                input_mem_r[(window_oh_i + kh) * IN_W + (window_ow_i + kw)];
        end
    end
endgenerate

endmodule
