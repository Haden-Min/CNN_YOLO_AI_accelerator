`timescale 1ns/1ps

module conv_input_mem #(
    parameter DATA_WIDTH = 8,
    parameter IC      = 1,
    parameter IN_H    = 5,
    parameter IN_W    = 5,
    parameter K_H     = 3,
    parameter K_W     = 3,

    parameter INPUT_SIZE = IC * IN_H * IN_W,
    parameter INPUT_ADDR_WIDTH = (INPUT_SIZE <= 1) ? 1 : $clog2(INPUT_SIZE)
)(
    input wire clk,
    input wire rst_n,

    input wire write_en_i,
    input wire [INPUT_ADDR_WIDTH-1:0] write_addr_i,
    input wire signed [DATA_WIDTH-1:0] write_data_i,

    input wire [INPUT_ADDR_WIDTH-1:0] window_base_addr_i,

    output wire signed [K_H*K_W*DATA_WIDTH-1:0] window_o
);

genvar lane;
generate
    for (lane = 0; lane < K_H*K_W; lane = lane + 1) begin : gen_input_bram_lane
        localparam integer KH_IDX = lane / K_W;
        localparam integer KW_IDX = lane % K_W;

        (* ram_style = "block" *) reg signed [DATA_WIDTH-1:0] mem_r [0:INPUT_SIZE-1];
        reg signed [DATA_WIDTH-1:0] lane_data_r;

        always @(posedge clk) begin
            if (write_en_i) begin
                mem_r[write_addr_i] <= write_data_i;
            end

            lane_data_r <= mem_r[window_base_addr_i + KH_IDX * IN_W + KW_IDX];
        end

        assign window_o[(lane+1)*DATA_WIDTH-1:lane*DATA_WIDTH] = lane_data_r;
    end
endgenerate

endmodule
