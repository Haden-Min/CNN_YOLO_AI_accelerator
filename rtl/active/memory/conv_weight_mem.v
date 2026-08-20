`timescale 1ns/1ps

module conv_weight_mem #(
    parameter DATA_WIDTH = 8,
    parameter IC      = 1,
    parameter OC      = 1,
    parameter K_H     = 3,
    parameter K_W     = 3,

    parameter WEIGHT_SIZE = OC * IC * K_H * K_W,
    parameter WEIGHT_ADDR_WIDTH = (WEIGHT_SIZE <= 1) ? 1 : $clog2(WEIGHT_SIZE)
)(
    input wire clk,
    input wire rst_n,

    input wire write_en_i,
    input wire [WEIGHT_ADDR_WIDTH-1:0] write_addr_i,
    input wire signed [DATA_WIDTH-1:0] write_data_i,

    input wire [WEIGHT_ADDR_WIDTH-1:0] window_base_addr_i,

    output wire signed [K_H*K_W*DATA_WIDTH-1:0] window_o
);

genvar lane;
generate
    for (lane = 0; lane < K_H*K_W; lane = lane + 1) begin : gen_weight_bram_lane
        // A 3x3, IC=1 packet stores only nine bytes per lane. Forcing each
        // lane into a RAMB18 wastes nine BRAMs and creates BRAM async-control
        // DRC warnings. LUTRAM is the intended implementation at this depth.
        (* ram_style = "distributed" *) reg signed [DATA_WIDTH-1:0] mem_r [0:WEIGHT_SIZE-1];
        reg signed [DATA_WIDTH-1:0] lane_data_r;

        always @(posedge clk) begin
            if (write_en_i) begin
                mem_r[write_addr_i] <= write_data_i;
            end

            lane_data_r <= mem_r[window_base_addr_i + lane];
        end

        assign window_o[(lane+1)*DATA_WIDTH-1:lane*DATA_WIDTH] = lane_data_r;
    end
endgenerate

endmodule
