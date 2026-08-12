`timescale 1ns/1ps

module tile_input_loader #(
    parameter DATA_WIDTH  = 8,
    parameter TILE_WIDTH  = 28,
    parameter TILE_HEIGHT = 28,
    parameter COL_WIDTH   = (TILE_WIDTH  <= 1) ? 1 : $clog2(TILE_WIDTH),
    parameter ROW_WIDTH   = (TILE_HEIGHT <= 1) ? 1 : $clog2(TILE_HEIGHT)
)(
    input wire clk,
    input wire rst_n,
    input wire start_i,
    input wire load_enable_i,

    input wire signed [DATA_WIDTH-1:0] s_data_i,
    input wire s_valid_i,
    output wire s_ready_o,
    input wire s_last_i,

    output wire write_en_o,
    output wire [1:0] write_bank_o,
    output wire [COL_WIDTH-1:0] write_col_o,
    output wire signed [DATA_WIDTH-1:0] write_data_o,

    output wire row_done_o,
    output wire tile_done_o,
    output wire active_o,
    output reg [1:0] error_o
);

reg active_r;
reg [1:0] bank_r;
reg [COL_WIDTH-1:0] col_r;
reg [ROW_WIDTH-1:0] row_r;

wire input_fire_w;
wire last_pixel_w;
wire last_col_w;

assign s_ready_o = active_r && load_enable_i;
assign input_fire_w = s_valid_i && s_ready_o;
assign last_col_w = (col_r == TILE_WIDTH - 1);
assign last_pixel_w = last_col_w && (row_r == TILE_HEIGHT - 1);

assign write_en_o = input_fire_w;
assign write_bank_o = bank_r;
assign write_col_o = col_r;
assign write_data_o = s_data_i;
assign active_o = active_r;
assign row_done_o = input_fire_w && last_col_w;
assign tile_done_o = input_fire_w && last_pixel_w;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        active_r   <= 1'b0;
        bank_r     <= 2'd0;
        col_r      <= {COL_WIDTH{1'b0}};
        row_r      <= {ROW_WIDTH{1'b0}};
        error_o    <= 2'b00;
    end
    else begin
        if (start_i) begin
            active_r <= 1'b1;
            bank_r   <= 2'd0;
            col_r    <= {COL_WIDTH{1'b0}};
            row_r    <= {ROW_WIDTH{1'b0}};
            error_o  <= 2'b00;
        end
        else if (input_fire_w) begin
            if (s_last_i && !last_pixel_w) begin
                error_o[0] <= 1'b1;
            end

            if (last_pixel_w && !s_last_i) begin
                error_o[1] <= 1'b1;
            end

            if (last_col_w) begin
                col_r <= {COL_WIDTH{1'b0}};

                if (bank_r == 2'd2) begin
                    bank_r <= 2'd0;
                end
                else begin
                    bank_r <= bank_r + 1'b1;
                end

                if (last_pixel_w) begin
                    active_r <= 1'b0;
                end
                else begin
                    row_r <= row_r + 1'b1;
                end
            end
            else begin
                col_r <= col_r + 1'b1;
            end
        end
    end
end

endmodule
