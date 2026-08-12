`timescale 1ns/1ps

module conv_control_unit #(
    parameter DATA_WIDTH = 8,
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
    parameter OUTPUT_ADDR_WIDTH = (OUTPUT_SIZE <= 1) ? 1 : $clog2(OUTPUT_SIZE)
)(
    input wire clk,
    input wire rst_n,
    input wire start_i,
    input wire input_window_valid_i,
    input wire datapath_result_valid_i,
    input wire datapath_result_ready_i,
    input wire [OUTPUT_ADDR_WIDTH-1:0] datapath_result_addr_i,

    output wire [INPUT_ADDR_WIDTH-1:0] input_base_addr_o,
    output wire [WEIGHT_ADDR_WIDTH-1:0] weight_base_addr_o,
    output wire [BIAS_ADDR_WIDTH-1:0] bias_addr_o,
    output wire [OUTPUT_ADDR_WIDTH-1:0] output_addr_o,

    output wire busy_o,
    output wire done_o,
    output wire input_window_req_o,
    output reg output_we_o,
    output reg mac_en_o,
    output reg mac_last_o,
    output reg acc_load_bias_o
);

wire fsm_output_we_w;
wire fsm_mac_en_w;
wire fsm_mac_last_w;
wire fsm_acc_load_bias_w;

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
    .input_window_valid_i(input_window_valid_i),
    .datapath_result_valid_i(datapath_result_valid_i),
    .datapath_result_ready_i(datapath_result_ready_i),
    .datapath_result_addr_i(datapath_result_addr_i),
    .input_addr_o(input_base_addr_o),
    .weight_addr_o(weight_base_addr_o),
    .bias_addr_o(bias_addr_o),
    .output_addr_o(output_addr_o),
    .busy_o(busy_o),
    .done_o(done_o),
    .output_we_o(fsm_output_we_w),
    .mac_en_o(fsm_mac_en_w),
    .mac_last_o(fsm_mac_last_w),
    .acc_load_bias_o(fsm_acc_load_bias_w),
    .input_window_req_o(input_window_req_o),
    .oc_counter_o(),
    .oh_counter_o(),
    .ow_counter_o(),
    .ic_counter_o()
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        output_we_o     <= 1'b0;
        mac_en_o        <= 1'b0;
        mac_last_o      <= 1'b0;
        acc_load_bias_o <= 1'b0;
    end
    else begin
        output_we_o     <= fsm_output_we_w;
        mac_en_o        <= fsm_mac_en_w;
        mac_last_o      <= fsm_mac_last_w;
        acc_load_bias_o <= fsm_acc_load_bias_w;
    end
end

endmodule
