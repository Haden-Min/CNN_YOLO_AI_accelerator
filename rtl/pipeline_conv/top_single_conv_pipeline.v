`timescale 1ns/1ps

module top_single_conv_pipeline #(
    parameter DATA_WIDTH = 8,
    parameter MUL_WIDTH  = 16,
    parameter ACC_WIDTH  = 32,

    parameter IC      = 1,
    parameter OC      = 1,
    parameter IN_H    = 5,
    parameter IN_W    = 5,
    parameter K_H     = 3,
    parameter K_W     = 3,
    parameter STRIDE  = 1,
    parameter PADDING = 0,
    parameter OUT_H   = 3,
    parameter OUT_W   = 3,

    parameter INPUT_SIZE  = IC * IN_H * IN_W,
    parameter WEIGHT_SIZE = OC * IC * K_H * K_W,
    parameter BIAS_SIZE   = OC,
    parameter OUTPUT_SIZE = OC * OUT_H * OUT_W,

    parameter INPUT_ADDR_WIDTH  = (INPUT_SIZE  <= 1) ? 1 : $clog2(INPUT_SIZE),
    parameter WEIGHT_ADDR_WIDTH = (WEIGHT_SIZE <= 1) ? 1 : $clog2(WEIGHT_SIZE),
    parameter BIAS_ADDR_WIDTH   = (BIAS_SIZE   <= 1) ? 1 : $clog2(BIAS_SIZE),
    parameter OUTPUT_ADDR_WIDTH = (OUTPUT_SIZE <= 1) ? 1 : $clog2(OUTPUT_SIZE),
    parameter OUT_H_WIDTH       = (OUT_H       <= 1) ? 1 : $clog2(OUT_H),
    parameter OUT_W_WIDTH       = (OUT_W       <= 1) ? 1 : $clog2(OUT_W)
)(
    input wire clk,
    input wire rst_n,
    input wire start_i,

    input wire input_load_en_i,
    input wire [INPUT_ADDR_WIDTH-1:0] input_load_addr_i,
    input wire signed [DATA_WIDTH-1:0] input_stream_data_i,

    input wire weight_load_en_i,
    input wire [WEIGHT_ADDR_WIDTH-1:0] weight_load_addr_i,
    input wire signed [DATA_WIDTH-1:0] weight_stream_data_i,

    input wire signed [ACC_WIDTH-1:0] bias_data_i,

    output wire [BIAS_ADDR_WIDTH-1:0] bias_addr_o,
    output wire [OUTPUT_ADDR_WIDTH-1:0] output_addr_o,
    output wire output_we_o,
    output wire busy_o,
    output wire done_o,

    output wire signed [ACC_WIDTH-1:0] output_data_o
);

wire [INPUT_ADDR_WIDTH-1:0] fsm_input_base_addr_w;
wire [WEIGHT_ADDR_WIDTH-1:0] fsm_weight_base_addr_w;
wire acc_load_bias_w;
wire mac_en_w;
wire [31:0] oh_counter_w;
wire [31:0] ow_counter_w;

wire signed [DATA_WIDTH-1:0] si_input_data_w;
wire signed [DATA_WIDTH-1:0] si_weight_data_w;

reg input_wbuf_we_r;
reg [INPUT_ADDR_WIDTH-1:0] input_wbuf_addr_r;
reg weight_buf_we_r;
reg [WEIGHT_ADDR_WIDTH-1:0] weight_buf_addr_r;

wire signed [K_H*K_W*DATA_WIDTH-1:0] input_window_w;
wire signed [K_H*K_W*DATA_WIDTH-1:0] weight_window_w;
wire signed [ACC_WIDTH-1:0] mac_sum_w;
wire signed [ACC_WIDTH-1:0] acc_w;

single_conv_fsm #(
    .DATA_WIDTH(DATA_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .IC(IC),
    .OC(OC),
    .IN_H(IN_H),
    .IN_W(IN_W),
    .K_H(K_H),
    .K_W(K_W),
    .STRIDE(STRIDE),
    .PADDING(PADDING),
    .OUT_H(OUT_H),
    .OUT_W(OUT_W),
    .PARALLEL_KERNEL(1)
) u_fsm (
    .clk_i(clk),
    .rst_n(rst_n),
    .start_i(start_i),
    .input_addr_o(fsm_input_base_addr_w),
    .weight_addr_o(fsm_weight_base_addr_w),
    .bias_addr_o(bias_addr_o),
    .output_addr_o(output_addr_o),
    .busy_o(busy_o),
    .done_o(done_o),
    .output_we_o(output_we_o),
    .mac_en_o(mac_en_w),
    .acc_load_bias_o(acc_load_bias_w),
    .oc_counter_o(),
    .oh_counter_o(oh_counter_w),
    .ow_counter_o(ow_counter_w),
    .ic_counter_o()
);

si #(
    .bit_width(DATA_WIDTH)
) u_input_si (
    .clk(clk),
    .en(input_load_en_i),
    .in(input_stream_data_i),
    .out(si_input_data_w)
);

si #(
    .bit_width(DATA_WIDTH)
) u_weight_si (
    .clk(clk),
    .en(weight_load_en_i),
    .in(weight_stream_data_i),
    .out(si_weight_data_w)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        input_wbuf_we_r   <= 1'b0;
        input_wbuf_addr_r <= {INPUT_ADDR_WIDTH{1'b0}};
        weight_buf_we_r   <= 1'b0;
        weight_buf_addr_r <= {WEIGHT_ADDR_WIDTH{1'b0}};
    end
    else begin
        input_wbuf_we_r   <= input_load_en_i;
        input_wbuf_addr_r <= input_load_addr_i;
        weight_buf_we_r   <= weight_load_en_i;
        weight_buf_addr_r <= weight_load_addr_i;
    end
end

wbuf #(
    .DATA_WIDTH(DATA_WIDTH),
    .IN_H(IN_H),
    .IN_W(IN_W),
    .K_H(K_H),
    .K_W(K_W),
    .ADDR_WIDTH(INPUT_ADDR_WIDTH),
    .OUT_H_WIDTH(OUT_H_WIDTH),
    .OUT_W_WIDTH(OUT_W_WIDTH)
) u_wbuf (
    .clk(clk),
    .rst_n(rst_n),
    .write_en_i(input_wbuf_we_r),
    .write_addr_i(input_wbuf_addr_r),
    .data_i(si_input_data_w),
    .window_oh_i(oh_counter_w[OUT_H_WIDTH-1:0]),
    .window_ow_i(ow_counter_w[OUT_W_WIDTH-1:0]),
    .window_o(input_window_w)
);

weight_buffer_9 #(
    .DATA_WIDTH(DATA_WIDTH),
    .K_H(K_H),
    .K_W(K_W),
    .ADDR_WIDTH(WEIGHT_ADDR_WIDTH)
) u_weight_buffer (
    .clk(clk),
    .rst_n(rst_n),
    .write_en_i(weight_buf_we_r),
    .write_addr_i(weight_buf_addr_r),
    .data_i(si_weight_data_w),
    .weight_o(weight_window_w)
);

mlt9_at #(
    .DATA_WIDTH(DATA_WIDTH),
    .MUL_WIDTH(MUL_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
) u_mlt9_at (
    .input_window_i(input_window_w),
    .weight_window_i(weight_window_w),
    .sum_o(mac_sum_w)
);

acc #(
    .IN_WIDTH(ACC_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
) u_acc (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(1'b0),
    .load_bias_i(acc_load_bias_w),
    .en_i(mac_en_w),
    .data_i(mac_sum_w),
    .bias_i(bias_data_i),
    .acc_o(acc_w)
);

activation #(
    .DATA_WIDTH(ACC_WIDTH)
) u_activation (
    .data_i(acc_w),
    .data_o(output_data_o)
);

endmodule
