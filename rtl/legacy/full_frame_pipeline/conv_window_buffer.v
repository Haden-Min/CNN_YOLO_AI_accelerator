`timescale 1ns/1ps

module conv_window_buffer #(
    parameter DATA_WIDTH = 8,
    parameter IC = 1,
    parameter IN_H = 5,
    parameter IN_W = 5,
    parameter K_H = 3,
    parameter K_W = 3,
    parameter STRIDE = 1,

    parameter INPUT_SIZE = IC * IN_H * IN_W,
    parameter INPUT_ADDR_WIDTH = (INPUT_SIZE <= 1) ? 1 : $clog2(INPUT_SIZE)
)(
    input wire clk,
    input wire rst_n,
    input wire request_i,
    input wire [INPUT_ADDR_WIDTH-1:0] window_base_addr_i,

    input wire signed [K_H*K_W*DATA_WIDTH-1:0] full_window_i,
    input wire full_window_valid_i,
    input wire signed [K_H*K_W*DATA_WIDTH-1:0] append_window_i,
    input wire append_window_valid_i,

    output wire signed [K_H*K_W*DATA_WIDTH-1:0] window_o,
    output wire window_ready_o
);

localparam FRAME_SIZE = IN_H * IN_W;
localparam SHIFT_COLS = (STRIDE < K_W) ? STRIDE : K_W;

reg signed [K_H*K_W*DATA_WIDTH-1:0] window_r;
reg window_valid_r;
reg [31:0] prev_ic_r;
reg [31:0] prev_row_r;
reg [31:0] prev_col_r;

wire [31:0] curr_ic_w;
wire [31:0] curr_frame_addr_w;
wire [31:0] curr_row_w;
wire [31:0] curr_col_w;
wire can_shift_w;
wire ready_w;

integer kh_idx;
integer kw_idx;
integer dst_lane_idx;
integer src_lane_idx;

assign curr_ic_w         = window_base_addr_i / FRAME_SIZE;
assign curr_frame_addr_w = window_base_addr_i % FRAME_SIZE;
assign curr_row_w        = curr_frame_addr_w / IN_W;
assign curr_col_w        = curr_frame_addr_w % IN_W;

assign can_shift_w = window_valid_r &&
                     (STRIDE < K_W) &&
                     (curr_ic_w == prev_ic_r) &&
                     (curr_row_w == prev_row_r) &&
                     (curr_col_w == prev_col_r + STRIDE);

assign ready_w = can_shift_w ? append_window_valid_i : full_window_valid_i;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        window_r       <= {K_H*K_W*DATA_WIDTH{1'b0}};
        window_valid_r <= 1'b0;
        prev_ic_r      <= 32'd0;
        prev_row_r     <= 32'd0;
        prev_col_r     <= 32'd0;
    end
    else if (request_i && ready_w) begin
        if (can_shift_w) begin
            for (kh_idx = 0; kh_idx < K_H; kh_idx = kh_idx + 1) begin
                for (kw_idx = 0; kw_idx < K_W; kw_idx = kw_idx + 1) begin
                    dst_lane_idx = kh_idx * K_W + kw_idx;

                    if (kw_idx < K_W - SHIFT_COLS) begin
                        src_lane_idx = kh_idx * K_W + kw_idx + SHIFT_COLS;
                        window_r[dst_lane_idx*DATA_WIDTH +: DATA_WIDTH] <=
                            window_r[src_lane_idx*DATA_WIDTH +: DATA_WIDTH];
                    end
                    else begin
                        window_r[dst_lane_idx*DATA_WIDTH +: DATA_WIDTH] <=
                            append_window_i[dst_lane_idx*DATA_WIDTH +: DATA_WIDTH];
                    end
                end
            end
        end
        else begin
            window_r <= full_window_i;
        end

        window_valid_r <= 1'b1;
        prev_ic_r      <= curr_ic_w;
        prev_row_r     <= curr_row_w;
        prev_col_r     <= curr_col_w;
    end
end

assign window_o = window_r;
assign window_ready_o = ready_w;

endmodule
