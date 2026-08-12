`timescale 1ns/1ps

module tile_conv_controller #(
    parameter TILE_WIDTH        = 28,
    parameter TILE_HEIGHT       = 28,
    parameter OUTPUT_WIDTH      = TILE_WIDTH - 2,
    parameter OUTPUT_HEIGHT     = TILE_HEIGHT - 2,
    parameter COL_WIDTH         = (TILE_WIDTH <= 1) ? 1 : $clog2(TILE_WIDTH),
    parameter OUT_COL_WIDTH     = (OUTPUT_WIDTH <= 1) ? 1 : $clog2(OUTPUT_WIDTH),
    parameter OUT_ROW_WIDTH     = (OUTPUT_HEIGHT <= 1) ? 1 : $clog2(OUTPUT_HEIGHT),
    parameter OUTPUT_SIZE       = OUTPUT_WIDTH * OUTPUT_HEIGHT,
    parameter OUTPUT_ADDR_WIDTH = (OUTPUT_SIZE <= 1) ? 1 : $clog2(OUTPUT_SIZE)
)(
    input wire clk,
    input wire rst_n,
    input wire start_i,

    input wire loader_row_done_i,
    input wire column_ready_i,
    input wire column_valid_i,
    input wire window_valid_i,
    input wire result_valid_i,
    input wire result_ready_i,

    output wire loader_start_o,
    output wire loader_enable_o,
    output wire line_read_en_o,
    output wire [1:0] line_top_bank_o,
    output wire [COL_WIDTH-1:0] line_read_col_o,
    output wire window_start_row_o,
    output wire window_ready_o,

    output wire acc_load_bias_o,
    output wire mac_en_o,
    output wire mac_last_o,
    output wire [OUTPUT_ADDR_WIDTH-1:0] output_addr_o,

    output wire busy_o,
    output reg done_o,
    output wire [3:0] state_o
);

localparam ST_IDLE         = 4'd0;
localparam ST_LOAD_INITIAL = 4'd1;
localparam ST_START_ROW    = 4'd2;
localparam ST_READ_REQ     = 4'd3;
localparam ST_READ_WAIT    = 4'd4;
localparam ST_WAIT_WINDOW  = 4'd5;
localparam ST_WAIT_RESULT  = 4'd6;
localparam ST_LOAD_NEXT    = 4'd7;

reg [3:0] state_r;
reg [1:0] initial_rows_r;
reg [1:0] top_bank_r;
reg [COL_WIDTH-1:0] read_col_r;
reg [OUT_COL_WIDTH-1:0] output_col_r;
reg [OUT_ROW_WIDTH-1:0] output_row_r;
reg [OUTPUT_ADDR_WIDTH-1:0] output_addr_r;

wire column_fire_w;
wire window_fire_w;
wire result_fire_w;

assign column_fire_w = column_valid_i && column_ready_i;
assign window_fire_w = window_valid_i && window_ready_o;
assign result_fire_w = result_valid_i && result_ready_i;

assign loader_start_o = start_i && (state_r == ST_IDLE);
assign loader_enable_o = (state_r == ST_LOAD_INITIAL) ||
                         (state_r == ST_LOAD_NEXT);
assign line_read_en_o = (state_r == ST_READ_REQ) && column_ready_i;
assign line_top_bank_o = top_bank_r;
assign line_read_col_o = read_col_r;
assign window_start_row_o = (state_r == ST_START_ROW);
assign window_ready_o = (state_r == ST_WAIT_WINDOW);

assign acc_load_bias_o = window_fire_w;
assign mac_en_o = window_fire_w;
assign mac_last_o = window_fire_w;
assign output_addr_o = output_addr_r;

assign busy_o = (state_r != ST_IDLE);
assign state_o = state_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_r <= ST_IDLE;
        initial_rows_r <= 2'd0;
        top_bank_r <= 2'd0;
        read_col_r <= {COL_WIDTH{1'b0}};
        output_col_r <= {OUT_COL_WIDTH{1'b0}};
        output_row_r <= {OUT_ROW_WIDTH{1'b0}};
        output_addr_r <= {OUTPUT_ADDR_WIDTH{1'b0}};
        done_o <= 1'b0;
    end
    else begin
        done_o <= 1'b0;

        case (state_r)
            ST_IDLE: begin
                if (start_i) begin
                    state_r <= ST_LOAD_INITIAL;
                    initial_rows_r <= 2'd0;
                    top_bank_r <= 2'd0;
                    read_col_r <= {COL_WIDTH{1'b0}};
                    output_col_r <= {OUT_COL_WIDTH{1'b0}};
                    output_row_r <= {OUT_ROW_WIDTH{1'b0}};
                    output_addr_r <= {OUTPUT_ADDR_WIDTH{1'b0}};
                end
            end

            ST_LOAD_INITIAL: begin
                if (loader_row_done_i) begin
                    if (initial_rows_r == 2'd2) begin
                        state_r <= ST_START_ROW;
                    end
                    else begin
                        initial_rows_r <= initial_rows_r + 1'b1;
                    end
                end
            end

            ST_START_ROW: begin
                read_col_r <= {COL_WIDTH{1'b0}};
                state_r <= ST_READ_REQ;
            end

            ST_READ_REQ: begin
                if (column_ready_i) begin
                    state_r <= ST_READ_WAIT;
                end
            end

            ST_READ_WAIT: begin
                if (column_fire_w) begin
                    if (read_col_r >= 2) begin
                        state_r <= ST_WAIT_WINDOW;
                    end
                    else begin
                        read_col_r <= read_col_r + 1'b1;
                        state_r <= ST_READ_REQ;
                    end
                end
            end

            ST_WAIT_WINDOW: begin
                if (window_fire_w) begin
                    state_r <= ST_WAIT_RESULT;
                end
            end

            ST_WAIT_RESULT: begin
                if (result_fire_w) begin
                    if (output_col_r == OUTPUT_WIDTH - 1) begin
                        output_col_r <= {OUT_COL_WIDTH{1'b0}};

                        if (output_row_r == OUTPUT_HEIGHT - 1) begin
                            done_o <= 1'b1;
                            state_r <= ST_IDLE;
                        end
                        else begin
                            output_addr_r <= output_addr_r + 1'b1;
                            state_r <= ST_LOAD_NEXT;
                        end
                    end
                    else begin
                        output_col_r <= output_col_r + 1'b1;
                        output_addr_r <= output_addr_r + 1'b1;
                        read_col_r <= read_col_r + 1'b1;
                        state_r <= ST_READ_REQ;
                    end
                end
            end

            ST_LOAD_NEXT: begin
                if (loader_row_done_i) begin
                    output_row_r <= output_row_r + 1'b1;

                    if (top_bank_r == 2'd2) begin
                        top_bank_r <= 2'd0;
                    end
                    else begin
                        top_bank_r <= top_bank_r + 1'b1;
                    end

                    state_r <= ST_START_ROW;
                end
            end

            default: begin
                state_r <= ST_IDLE;
            end
        endcase
    end
end

endmodule
