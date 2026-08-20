`timescale 1ns/1ps

module tile_line_buffer_3row #(
    parameter DATA_WIDTH = 8,
    parameter TILE_WIDTH = 28,
    parameter COL_WIDTH  = (TILE_WIDTH <= 1) ? 1 : $clog2(TILE_WIDTH)
)(
    input wire clk,
    input wire rst_n,

    input wire write_en_i,
    input wire [1:0] write_bank_i,
    input wire [COL_WIDTH-1:0] write_col_i,
    input wire signed [DATA_WIDTH-1:0] write_data_i,

    input wire read_en_i,
    input wire [1:0] top_bank_i,
    input wire [COL_WIDTH-1:0] read_col_i,

    output reg signed [3*DATA_WIDTH-1:0] column_o,
    output reg column_valid_o
);

(* ram_style = "distributed" *) reg signed [DATA_WIDTH-1:0] bank0_r [0:TILE_WIDTH-1];
(* ram_style = "distributed" *) reg signed [DATA_WIDTH-1:0] bank1_r [0:TILE_WIDTH-1];
(* ram_style = "distributed" *) reg signed [DATA_WIDTH-1:0] bank2_r [0:TILE_WIDTH-1];

reg signed [DATA_WIDTH-1:0] bank0_read_r;
reg signed [DATA_WIDTH-1:0] bank1_read_r;
reg signed [DATA_WIDTH-1:0] bank2_read_r;
reg [1:0] read_top_bank_r;
reg read_valid_r;

always @(posedge clk) begin
    if (write_en_i) begin
        case (write_bank_i)
            2'd0: bank0_r[write_col_i] <= write_data_i;
            2'd1: bank1_r[write_col_i] <= write_data_i;
            2'd2: bank2_r[write_col_i] <= write_data_i;
            default: bank0_r[write_col_i] <= write_data_i;
        endcase
    end

    if (read_en_i) begin
        bank0_read_r <= bank0_r[read_col_i];
        bank1_read_r <= bank1_r[read_col_i];
        bank2_read_r <= bank2_r[read_col_i];
        read_top_bank_r <= top_bank_i;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        read_valid_r <= 1'b0;
        column_valid_o <= 1'b0;
        column_o <= {3*DATA_WIDTH{1'b0}};
    end
    else begin
        read_valid_r <= read_en_i;
        column_valid_o <= read_valid_r;

        if (read_valid_r) begin
            case (read_top_bank_r)
                2'd0: begin
                    column_o[DATA_WIDTH-1:0] <= bank0_read_r;
                    column_o[2*DATA_WIDTH-1:DATA_WIDTH] <= bank1_read_r;
                    column_o[3*DATA_WIDTH-1:2*DATA_WIDTH] <= bank2_read_r;
                end
                2'd1: begin
                    column_o[DATA_WIDTH-1:0] <= bank1_read_r;
                    column_o[2*DATA_WIDTH-1:DATA_WIDTH] <= bank2_read_r;
                    column_o[3*DATA_WIDTH-1:2*DATA_WIDTH] <= bank0_read_r;
                end
                default: begin
                    column_o[DATA_WIDTH-1:0] <= bank2_read_r;
                    column_o[2*DATA_WIDTH-1:DATA_WIDTH] <= bank0_read_r;
                    column_o[3*DATA_WIDTH-1:2*DATA_WIDTH] <= bank1_read_r;
                end
            endcase
        end
    end
end

endmodule
