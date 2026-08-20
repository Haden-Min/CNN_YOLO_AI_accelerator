`timescale 1ns/1ps

module conv_input_line_buffer #(
    parameter DATA_WIDTH = 8,
    parameter IC      = 1,
    parameter IN_H    = 5,
    parameter IN_W    = 5,
    parameter K_H     = 3,
    parameter K_W     = 3,
    parameter STRIDE  = 1,

    parameter INPUT_SIZE = IC * IN_H * IN_W,
    parameter INPUT_ADDR_WIDTH = (INPUT_SIZE <= 1) ? 1 : $clog2(INPUT_SIZE)
)(
    input wire clk,
    input wire rst_n,

    input wire write_en_i,
    input wire [INPUT_ADDR_WIDTH-1:0] write_addr_i,
    input wire signed [DATA_WIDTH-1:0] write_data_i,

    input wire [INPUT_ADDR_WIDTH-1:0] window_base_addr_i,

    output wire signed [K_H*K_W*DATA_WIDTH-1:0] full_window_o,
    output wire full_window_valid_o,
    output wire signed [K_H*K_W*DATA_WIDTH-1:0] append_window_o,
    output wire append_window_valid_o
);

localparam FRAME_SIZE = IN_H * IN_W;
localparam SHIFT_COLS = (STRIDE < K_W) ? STRIDE : K_W;

(* ram_style = "distributed" *) reg signed [DATA_WIDTH-1:0] line_mem_r [0:K_H-1][0:IN_W-1];
reg [31:0] row_tag_r [0:K_H-1];
reg [31:0] ic_tag_r [0:K_H-1];
reg [IN_W-1:0] col_valid_r [0:K_H-1];
reg row_valid_r [0:K_H-1];

wire [31:0] write_ic_w;
wire [31:0] write_frame_addr_w;
wire [31:0] write_row_w;
wire [31:0] write_col_w;
wire [31:0] write_slot_w;

wire [31:0] base_ic_w;
wire [31:0] base_frame_addr_w;
wire [31:0] base_row_w;
wire [31:0] base_col_w;

reg signed [K_H*K_W*DATA_WIDTH-1:0] window_data_r;
reg window_valid_r;
reg signed [K_H*K_W*DATA_WIDTH-1:0] append_data_r;
reg append_valid_r;
reg [IN_W-1:0] write_col_mask_r;

integer reset_row_idx;
integer reset_col_idx;
integer kh_idx;
integer kw_idx;
integer lane_idx;
integer row_idx;
integer col_idx;
integer slot_idx;

assign write_ic_w         = write_addr_i / FRAME_SIZE;
assign write_frame_addr_w = write_addr_i % FRAME_SIZE;
assign write_row_w        = write_frame_addr_w / IN_W;
assign write_col_w        = write_frame_addr_w % IN_W;
assign write_slot_w       = write_row_w % K_H;

assign base_ic_w          = window_base_addr_i / FRAME_SIZE;
assign base_frame_addr_w  = window_base_addr_i % FRAME_SIZE;
assign base_row_w         = base_frame_addr_w / IN_W;
assign base_col_w         = base_frame_addr_w % IN_W;

always @(*) begin
    write_col_mask_r = {IN_W{1'b0}};
    if (write_col_w < IN_W) begin
        write_col_mask_r[write_col_w] = 1'b1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (reset_row_idx = 0; reset_row_idx < K_H; reset_row_idx = reset_row_idx + 1) begin
            row_tag_r[reset_row_idx]   <= 32'd0;
            ic_tag_r[reset_row_idx]    <= 32'd0;
            col_valid_r[reset_row_idx] <= {IN_W{1'b0}};
            row_valid_r[reset_row_idx] <= 1'b0;

            for (reset_col_idx = 0; reset_col_idx < IN_W; reset_col_idx = reset_col_idx + 1) begin
                line_mem_r[reset_row_idx][reset_col_idx] <= {DATA_WIDTH{1'b0}};
            end
        end
    end
    else if (write_en_i) begin
        for (reset_row_idx = 0; reset_row_idx < K_H; reset_row_idx = reset_row_idx + 1) begin
            if (write_slot_w == reset_row_idx) begin
                for (reset_col_idx = 0; reset_col_idx < IN_W; reset_col_idx = reset_col_idx + 1) begin
                    if (write_col_w == reset_col_idx) begin
                        line_mem_r[reset_row_idx][reset_col_idx] <= write_data_i;
                    end
                end

                if (write_col_w == 0) begin
                    row_tag_r[reset_row_idx]   <= write_row_w;
                    ic_tag_r[reset_row_idx]    <= write_ic_w;
                    col_valid_r[reset_row_idx] <= write_col_mask_r;
                    row_valid_r[reset_row_idx] <= 1'b1;
                end
                else begin
                    col_valid_r[reset_row_idx] <= col_valid_r[reset_row_idx] | write_col_mask_r;
                end
            end
        end
    end
end

always @(*) begin
    window_data_r  = {K_H*K_W*DATA_WIDTH{1'b0}};
    window_valid_r = 1'b1;
    append_data_r  = {K_H*K_W*DATA_WIDTH{1'b0}};
    append_valid_r = 1'b1;

    for (kh_idx = 0; kh_idx < K_H; kh_idx = kh_idx + 1) begin
        for (kw_idx = 0; kw_idx < K_W; kw_idx = kw_idx + 1) begin
            lane_idx = kh_idx * K_W + kw_idx;
            row_idx  = base_row_w + kh_idx;
            col_idx  = base_col_w + kw_idx;
            slot_idx = row_idx % K_H;

            if ((row_idx >= IN_H) || (col_idx >= IN_W)) begin
                window_valid_r = 1'b0;
            end
            else begin
                window_data_r[lane_idx*DATA_WIDTH +: DATA_WIDTH] = line_mem_r[slot_idx][col_idx];

                if (!row_valid_r[slot_idx] ||
                    (row_tag_r[slot_idx] != row_idx) ||
                    (ic_tag_r[slot_idx] != base_ic_w) ||
                    !col_valid_r[slot_idx][col_idx]) begin
                    window_valid_r = 1'b0;
                end

                if (kw_idx >= K_W - SHIFT_COLS) begin
                    append_data_r[lane_idx*DATA_WIDTH +: DATA_WIDTH] = line_mem_r[slot_idx][col_idx];

                    if (!row_valid_r[slot_idx] ||
                        (row_tag_r[slot_idx] != row_idx) ||
                        (ic_tag_r[slot_idx] != base_ic_w) ||
                        !col_valid_r[slot_idx][col_idx]) begin
                        append_valid_r = 1'b0;
                    end
                end
            end
        end
    end
end

assign full_window_o = window_data_r;
assign full_window_valid_o = window_valid_r;
assign append_window_o = append_data_r;
assign append_window_valid_o = append_valid_r;

endmodule
