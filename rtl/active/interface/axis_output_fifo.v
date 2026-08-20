`timescale 1ns/1ps

module axis_output_fifo #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH = 16,
    parameter PTR_WIDTH = (DEPTH <= 2) ? 1 : $clog2(DEPTH),
    parameter COUNT_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1)
)(
    input wire clk,
    input wire rst_n,
    input wire clear_i,

    input wire [DATA_WIDTH-1:0] s_data_i,
    input wire s_last_i,
    input wire s_valid_i,
    output wire s_ready_o,

    output wire [DATA_WIDTH-1:0] m_data_o,
    output wire m_last_o,
    output wire m_valid_o,
    input wire m_ready_i,

    output wire [COUNT_WIDTH-1:0] level_o
);

(* ram_style = "distributed" *) reg [DATA_WIDTH-1:0] data_mem_r [0:DEPTH-1];
(* ram_style = "distributed" *) reg last_mem_r [0:DEPTH-1];
reg [PTR_WIDTH-1:0] write_ptr_r;
reg [PTR_WIDTH-1:0] read_ptr_r;
reg [COUNT_WIDTH-1:0] count_r;

wire push_w;
wire pop_w;

assign s_ready_o = (count_r < DEPTH);
assign m_valid_o = (count_r != 0);
assign m_data_o = data_mem_r[read_ptr_r];
assign m_last_o = last_mem_r[read_ptr_r];
assign level_o = count_r;

assign push_w = s_valid_i && s_ready_o;
assign pop_w = m_valid_o && m_ready_i;

always @(posedge clk) begin
    if (rst_n && !clear_i && push_w) begin
        data_mem_r[write_ptr_r] <= s_data_i;
        last_mem_r[write_ptr_r] <= s_last_i;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        write_ptr_r <= {PTR_WIDTH{1'b0}};
        read_ptr_r <= {PTR_WIDTH{1'b0}};
        count_r <= {COUNT_WIDTH{1'b0}};
    end
    else if (clear_i) begin
        write_ptr_r <= {PTR_WIDTH{1'b0}};
        read_ptr_r <= {PTR_WIDTH{1'b0}};
        count_r <= {COUNT_WIDTH{1'b0}};
    end
    else begin
        if (push_w) begin
            if (write_ptr_r == DEPTH - 1) begin
                write_ptr_r <= {PTR_WIDTH{1'b0}};
            end
            else begin
                write_ptr_r <= write_ptr_r + 1'b1;
            end
        end

        if (pop_w) begin
            if (read_ptr_r == DEPTH - 1) begin
                read_ptr_r <= {PTR_WIDTH{1'b0}};
            end
            else begin
                read_ptr_r <= read_ptr_r + 1'b1;
            end
        end

        case ({push_w, pop_w})
            2'b10: count_r <= count_r + 1'b1;
            2'b01: count_r <= count_r - 1'b1;
            default: count_r <= count_r;
        endcase
    end
end

endmodule
