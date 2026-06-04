module single_conv_control #(
    parameter INPUT_W  = 5,
    parameter INPUT_H  = 5,
    parameter KERNEL   = 3,
    parameter OUTPUT_W = 3,
    parameter OUTPUT_H = 3,

    parameter INPUT_ADDR_WIDTH  = 5, // 5x5 = 25 -> 0~24
    parameter WEIGHT_ADDR_WIDTH = 4, // 3x3 = 9  -> 0~8
    parameter OUTPUT_ADDR_WIDTH = 4, // 3x3 = 9  -> 0~8

    parameter OUT_POS_WIDTH = 2,     // 0~2
    parameter K_POS_WIDTH   = 2      // 0~2
)(
    input wire clk,
    input wire rst_n,
    input wire start_i,

    output reg busy_o,
    output reg done_o,

    output reg acc_clear_o,
    output reg acc_load_bias_o,
    output reg mac_en_o,
    output reg output_we_o,

    output reg [INPUT_ADDR_WIDTH-1:0]  input_addr_o,
    output reg [WEIGHT_ADDR_WIDTH-1:0] weight_addr_o,
    output reg [OUTPUT_ADDR_WIDTH-1:0] output_addr_o
);

localparam IDLE      = 3'd0;
localparam LOAD_BIAS = 3'd1;
localparam MAC       = 3'd2;
localparam WRITE_OUT = 3'd3;
localparam DONE      = 3'd4;

localparam INPUT_POS_WIDTH =
    (OUT_POS_WIDTH > K_POS_WIDTH) ? (OUT_POS_WIDTH + 1) : (K_POS_WIDTH + 1);

reg [2:0] state_r, state_n;

reg [OUT_POS_WIDTH-1:0] oh_r;
reg [OUT_POS_WIDTH-1:0] ow_r;
reg [K_POS_WIDTH-1:0]   kh_r;
reg [K_POS_WIDTH-1:0]   kw_r;

wire last_kernel_w;
wire last_output_w;

wire [INPUT_POS_WIDTH-1:0] input_row_w;
wire [INPUT_POS_WIDTH-1:0] input_col_w;

assign last_kernel_w = (kh_r == KERNEL-1) && (kw_r == KERNEL-1);
assign last_output_w = (oh_r == OUTPUT_H-1) && (ow_r == OUTPUT_W-1);

assign input_row_w = oh_r + kh_r;
assign input_col_w = ow_r + kw_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_r <= IDLE;
        oh_r <= 0;
        ow_r <= 0;
        kh_r <= 0;
        kw_r <= 0;
    end else begin

        state_r <= state_n;

        case (state_r)
            IDLE: begin
                oh_r <= 0;
                ow_r <= 0;
                kh_r <= 0;
                kw_r <= 0;
            end

            LOAD_BIAS: begin
                kh_r <= 0;
                kw_r <= 0;
            end

            MAC: begin
                if (!last_kernel_w) begin
                    if (kw_r == KERNEL-1) begin
                        kw_r <= 0;
                        kh_r <= kh_r + 1;
                    end else begin
                        kw_r <= kw_r + 1;
                    end
                end
            end

            WRITE_OUT: begin
                kh_r <= 0;
                kw_r <= 0;

                if (!last_output_w) begin
                    if (ow_r == OUTPUT_W-1) begin
                        ow_r <= 0;
                        oh_r <= oh_r + 1;
                    end else begin
                        ow_r <= ow_r + 1;
                    end
                end
            end
        endcase
    end
end

always @(*) begin
    state_n = state_r;

    case (state_r)
        IDLE: begin
            if (start_i)
                state_n = LOAD_BIAS;
        end

        LOAD_BIAS: begin
            state_n = MAC;
        end

        MAC: begin
            if (last_kernel_w)
                state_n = WRITE_OUT;
            else
                state_n = MAC;
        end

        WRITE_OUT: begin
            if (last_output_w)
                state_n = DONE;
            else
                state_n = LOAD_BIAS;
        end

        DONE: begin
            state_n = IDLE;
        end

        default: begin
            state_n = IDLE;
        end
    endcase
end

always @(*) begin
    busy_o          = 1'b0;
    done_o          = 1'b0;
    acc_clear_o     = 1'b0;
    acc_load_bias_o = 1'b0;
    mac_en_o        = 1'b0;
    output_we_o     = 1'b0;

    input_addr_o  = input_row_w * INPUT_W + input_col_w;
    weight_addr_o = kh_r * KERNEL + kw_r;
    output_addr_o = oh_r * OUTPUT_W + ow_r;

    case (state_r)
        LOAD_BIAS: begin
            busy_o          = 1'b1;
            acc_clear_o     = 1'b0;
            acc_load_bias_o = 1'b1;
        end

        MAC: begin
            busy_o   = 1'b1;
            mac_en_o = 1'b1;
        end

        WRITE_OUT: begin
            busy_o      = 1'b1;
            output_we_o = 1'b1;
        end

        DONE: begin
            done_o = 1'b1;
        end
    endcase
end

endmodule