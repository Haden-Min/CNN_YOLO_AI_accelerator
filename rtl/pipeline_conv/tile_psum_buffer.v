`timescale 1ns/1ps

// Accumulates one spatial convolution result per input channel.
//
// The first input channel overwrites every address with bias + channel_sum,
// so the RAM does not need a layer-wide clear. Intermediate channels update
// the stored partial sum. The final channel is forwarded to the output stream
// and is intentionally not written back to RAM.
module tile_psum_buffer #(
    parameter DATA_WIDTH = 32,
    parameter OUTPUT_SIZE = 676,
    parameter ADDR_WIDTH = (OUTPUT_SIZE <= 1) ? 1 : $clog2(OUTPUT_SIZE)
)(
    input wire clk,
    input wire rst_n,

    input wire signed [DATA_WIDTH-1:0] channel_data_i,
    input wire [ADDR_WIDTH-1:0] channel_addr_i,
    input wire channel_last_i,
    input wire channel_valid_i,
    output wire channel_ready_o,

    input wire first_channel_i,
    input wire last_channel_i,
    input wire signed [DATA_WIDTH-1:0] bias_i,

    output wire signed [DATA_WIDTH-1:0] result_data_o,
    output wire [ADDR_WIDTH-1:0] result_addr_o,
    output wire result_last_o,
    output wire result_valid_o,
    input wire result_ready_i,

    output wire busy_o
);

localparam ST_IDLE = 2'd0;
localparam ST_ACCUMULATE = 2'd1;
localparam ST_OUTPUT = 2'd2;

(* ram_style = "block" *) reg signed [DATA_WIDTH-1:0] psum_mem_r [0:OUTPUT_SIZE-1];

reg [1:0] state_r;
reg signed [DATA_WIDTH-1:0] read_data_r;
reg signed [DATA_WIDTH-1:0] channel_data_r;
reg signed [DATA_WIDTH-1:0] bias_r;
reg [ADDR_WIDTH-1:0] channel_addr_r;
reg channel_last_r;
reg first_channel_r;
reg last_channel_r;

reg signed [DATA_WIDTH-1:0] result_data_r;
reg [ADDR_WIDTH-1:0] result_addr_r;
reg result_last_r;
reg result_valid_r;

wire channel_fire_w;
wire signed [DATA_WIDTH-1:0] accumulated_w;

assign channel_ready_o = (state_r == ST_IDLE);
assign channel_fire_w = channel_valid_i && channel_ready_o;
assign accumulated_w = first_channel_r ?
                       (bias_r + channel_data_r) :
                       (read_data_r + channel_data_r);

assign result_data_o = result_data_r;
assign result_addr_o = result_addr_r;
assign result_last_o = result_last_r;
assign result_valid_o = result_valid_r;
assign busy_o = (state_r != ST_IDLE);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_r <= ST_IDLE;
        channel_data_r <= {DATA_WIDTH{1'b0}};
        bias_r <= {DATA_WIDTH{1'b0}};
        channel_addr_r <= {ADDR_WIDTH{1'b0}};
        channel_last_r <= 1'b0;
        first_channel_r <= 1'b0;
        last_channel_r <= 1'b0;
        result_data_r <= {DATA_WIDTH{1'b0}};
        result_addr_r <= {ADDR_WIDTH{1'b0}};
        result_last_r <= 1'b0;
        result_valid_r <= 1'b0;
    end
    else begin
        case (state_r)
            ST_IDLE: begin
                if (channel_fire_w) begin
                    channel_data_r <= channel_data_i;
                    bias_r <= bias_i;
                    channel_addr_r <= channel_addr_i;
                    channel_last_r <= channel_last_i;
                    first_channel_r <= first_channel_i;
                    last_channel_r <= last_channel_i;
                    state_r <= ST_ACCUMULATE;
                end
            end

            ST_ACCUMULATE: begin
                if (last_channel_r) begin
                    result_data_r <= accumulated_w;
                    result_addr_r <= channel_addr_r;
                    result_last_r <= channel_last_r;
                    result_valid_r <= 1'b1;
                    state_r <= ST_OUTPUT;
                end
                else begin
                    state_r <= ST_IDLE;
                end
            end

            ST_OUTPUT: begin
                if (result_valid_r && result_ready_i) begin
                    result_valid_r <= 1'b0;
                    result_last_r <= 1'b0;
                    state_r <= ST_IDLE;
                end
            end

            default: begin
                state_r <= ST_IDLE;
                result_valid_r <= 1'b0;
            end
        endcase
    end
end

// Keep the RAM in a reset-free, clocked process. A memory written from an
// asynchronously reset process cannot map to a Xilinx 7-series block RAM.
always @(posedge clk) begin
    if (channel_fire_w && !first_channel_i) begin
        read_data_r <= psum_mem_r[channel_addr_i];
    end

    if ((state_r == ST_ACCUMULATE) && !last_channel_r) begin
        psum_mem_r[channel_addr_r] <= accumulated_w;
    end
end

endmodule
