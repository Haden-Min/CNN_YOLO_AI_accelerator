`timescale 1ns/1ps

module tile_window_generator_3x3 #(
    parameter DATA_WIDTH = 8,
    parameter TILE_WIDTH = 28,
    parameter COL_WIDTH  = (TILE_WIDTH <= 1) ? 1 : $clog2(TILE_WIDTH)
)(
    input wire clk,
    input wire rst_n,
    input wire start_row_i,

    input wire signed [3*DATA_WIDTH-1:0] column_i,
    input wire column_valid_i,
    output wire column_ready_o,

    output wire signed [9*DATA_WIDTH-1:0] window_o,
    output wire [COL_WIDTH-1:0] window_col_o,
    output wire window_last_o,
    output wire window_valid_o,
    input wire window_ready_i
);

reg signed [DATA_WIDTH-1:0] top_prev2_r;
reg signed [DATA_WIDTH-1:0] top_prev1_r;
reg signed [DATA_WIDTH-1:0] mid_prev2_r;
reg signed [DATA_WIDTH-1:0] mid_prev1_r;
reg signed [DATA_WIDTH-1:0] bot_prev2_r;
reg signed [DATA_WIDTH-1:0] bot_prev1_r;

reg [COL_WIDTH-1:0] column_count_r;
reg signed [9*DATA_WIDTH-1:0] window_r;
reg [COL_WIDTH-1:0] window_col_r;
reg window_last_r;
reg window_valid_r;

wire signed [DATA_WIDTH-1:0] top_new_w;
wire signed [DATA_WIDTH-1:0] mid_new_w;
wire signed [DATA_WIDTH-1:0] bot_new_w;
wire column_fire_w;

assign top_new_w = column_i[DATA_WIDTH-1:0];
assign mid_new_w = column_i[2*DATA_WIDTH-1:DATA_WIDTH];
assign bot_new_w = column_i[3*DATA_WIDTH-1:2*DATA_WIDTH];

assign column_ready_o = !window_valid_r || window_ready_i;
assign column_fire_w = column_valid_i && column_ready_o;

assign window_o = window_r;
assign window_col_o = window_col_r;
assign window_last_o = window_last_r;
assign window_valid_o = window_valid_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        top_prev2_r <= {DATA_WIDTH{1'b0}};
        top_prev1_r <= {DATA_WIDTH{1'b0}};
        mid_prev2_r <= {DATA_WIDTH{1'b0}};
        mid_prev1_r <= {DATA_WIDTH{1'b0}};
        bot_prev2_r <= {DATA_WIDTH{1'b0}};
        bot_prev1_r <= {DATA_WIDTH{1'b0}};
        column_count_r <= {COL_WIDTH{1'b0}};
        window_r <= {9*DATA_WIDTH{1'b0}};
        window_col_r <= {COL_WIDTH{1'b0}};
        window_last_r <= 1'b0;
        window_valid_r <= 1'b0;
    end
    else if (start_row_i) begin
        top_prev2_r <= {DATA_WIDTH{1'b0}};
        top_prev1_r <= {DATA_WIDTH{1'b0}};
        mid_prev2_r <= {DATA_WIDTH{1'b0}};
        mid_prev1_r <= {DATA_WIDTH{1'b0}};
        bot_prev2_r <= {DATA_WIDTH{1'b0}};
        bot_prev1_r <= {DATA_WIDTH{1'b0}};
        column_count_r <= {COL_WIDTH{1'b0}};
        window_last_r <= 1'b0;
        window_valid_r <= 1'b0;
    end
    else begin
        if (window_valid_r && window_ready_i) begin
            window_valid_r <= 1'b0;
        end

        if (column_fire_w) begin
            if (column_count_r >= 2) begin
                window_r[1*DATA_WIDTH-1:0*DATA_WIDTH] <= top_prev2_r;
                window_r[2*DATA_WIDTH-1:1*DATA_WIDTH] <= top_prev1_r;
                window_r[3*DATA_WIDTH-1:2*DATA_WIDTH] <= top_new_w;
                window_r[4*DATA_WIDTH-1:3*DATA_WIDTH] <= mid_prev2_r;
                window_r[5*DATA_WIDTH-1:4*DATA_WIDTH] <= mid_prev1_r;
                window_r[6*DATA_WIDTH-1:5*DATA_WIDTH] <= mid_new_w;
                window_r[7*DATA_WIDTH-1:6*DATA_WIDTH] <= bot_prev2_r;
                window_r[8*DATA_WIDTH-1:7*DATA_WIDTH] <= bot_prev1_r;
                window_r[9*DATA_WIDTH-1:8*DATA_WIDTH] <= bot_new_w;
                window_col_r <= column_count_r - 2'd2;
                window_last_r <= (column_count_r == TILE_WIDTH - 1);
                window_valid_r <= 1'b1;
            end

            top_prev2_r <= top_prev1_r;
            top_prev1_r <= top_new_w;
            mid_prev2_r <= mid_prev1_r;
            mid_prev1_r <= mid_new_w;
            bot_prev2_r <= bot_prev1_r;
            bot_prev1_r <= bot_new_w;

            if (column_count_r != TILE_WIDTH - 1) begin
                column_count_r <= column_count_r + 1'b1;
            end
        end
    end
end

endmodule
