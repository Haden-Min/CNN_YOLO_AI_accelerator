`timescale 1ns/1ps

module conv_datapath #(
    parameter DATA_WIDTH        = 8,
    parameter MUL_WIDTH         = 16,
    parameter ACC_WIDTH         = 32,
    parameter K_H               = 3,
    parameter K_W               = 3,
    parameter OUTPUT_ADDR_WIDTH = 4,
    parameter ACC_BANK_SIZE     = 9,
    parameter ENABLE_ACTIVATION = 0,
    parameter LEAKY_SHIFT       = 3
)(
    input wire clk,
    input wire rst_n,

    input wire acc_load_bias_i,
    input wire mac_en_i,
    input wire mac_last_i,
    input wire [OUTPUT_ADDR_WIDTH-1:0] output_addr_i,
    input wire result_ready_i,

    input wire signed [K_H*K_W*DATA_WIDTH-1:0] input_window_i,
    input wire signed [K_H*K_W*DATA_WIDTH-1:0] weight_window_i,
    input wire signed [ACC_WIDTH-1:0] bias_i,

    output wire signed [ACC_WIDTH-1:0] acc_o,
    output wire result_valid_o,
    output wire [OUTPUT_ADDR_WIDTH-1:0] result_addr_o,
    output wire signed [ACC_WIDTH-1:0] result_o,
    output wire busy_o
);

localparam BANK_ID_WIDTH = (ACC_BANK_SIZE <= 1) ? 1 : $clog2(ACC_BANK_SIZE);

wire [BANK_ID_WIDTH-1:0] issue_bank_w;
wire signed [DATA_WIDTH-1:0] input_lane_w  [0:8];
wire signed [DATA_WIDTH-1:0] weight_lane_w [0:8];
wire signed [MUL_WIDTH-1:0]  mul_lane_w    [0:8];

reg signed [MUL_WIDTH-1:0] mul_stage_r [0:8];
reg mlt_valid_r;
reg mlt_last_r;
reg [OUTPUT_ADDR_WIDTH-1:0] mlt_addr_r;
reg [BANK_ID_WIDTH-1:0] mlt_bank_r;

wire signed [ACC_WIDTH-1:0] at_sum_w;
reg signed [ACC_WIDTH-1:0] at_sum_r;
reg at_valid_r;
reg at_last_r;
reg [OUTPUT_ADDR_WIDTH-1:0] at_addr_r;
reg [BANK_ID_WIDTH-1:0] at_bank_r;

wire signed [ACC_WIDTH-1:0] acc_bank_w [0:ACC_BANK_SIZE-1];
wire signed [ACC_WIDTH-1:0] acc_selected_w;
wire signed [ACC_WIDTH-1:0] acc_next_w;
wire signed [ACC_WIDTH-1:0] activated_w;
wire signed [ACC_WIDTH-1:0] atv_data_w;

reg result_valid_r;
reg [OUTPUT_ADDR_WIDTH-1:0] result_addr_r;
reg signed [ACC_WIDTH-1:0] result_data_r;

integer i;
genvar lane;
genvar bank;

assign issue_bank_w = output_addr_i % ACC_BANK_SIZE;

generate
    for (lane = 0; lane < 9; lane = lane + 1) begin : gen_mlt_lane
        assign input_lane_w[lane] =
            input_window_i[(lane+1)*DATA_WIDTH-1:lane*DATA_WIDTH];
        assign weight_lane_w[lane] =
            weight_window_i[(lane+1)*DATA_WIDTH-1:lane*DATA_WIDTH];

        mlt #(
            .DATA_WIDTH(DATA_WIDTH)
        ) u_mlt (
            .data_i(input_lane_w[lane]),
            .kernel_i(weight_lane_w[lane]),
            .mul_o(mul_lane_w[lane])
        );
    end
endgenerate

at #(
    .IN_WIDTH(MUL_WIDTH),
    .OUT_WIDTH(ACC_WIDTH)
) u_at (
    .mul0_i(mul_stage_r[0]),
    .mul1_i(mul_stage_r[1]),
    .mul2_i(mul_stage_r[2]),
    .mul3_i(mul_stage_r[3]),
    .mul4_i(mul_stage_r[4]),
    .mul5_i(mul_stage_r[5]),
    .mul6_i(mul_stage_r[6]),
    .mul7_i(mul_stage_r[7]),
    .mul8_i(mul_stage_r[8]),
    .sum_o(at_sum_w)
);

generate
    for (bank = 0; bank < ACC_BANK_SIZE; bank = bank + 1) begin : gen_acc_bank
        acc #(
            .IN_WIDTH(ACC_WIDTH),
            .ACC_WIDTH(ACC_WIDTH)
        ) u_acc (
            .clk(clk),
            .rst_n(rst_n),
            .clear_i(1'b0),
            .load_bias_i(acc_load_bias_i && (issue_bank_w == bank)),
            .en_i(at_valid_r && (at_bank_r == bank)),
            .data_i(at_sum_r),
            .bias_i(bias_i),
            .acc_o(acc_bank_w[bank])
        );
    end
endgenerate

assign acc_selected_w = acc_bank_w[at_bank_r];
assign acc_next_w = acc_selected_w + at_sum_r;

activation #(
    .DATA_WIDTH(ACC_WIDTH),
    .LEAKY_SHIFT(LEAKY_SHIFT)
) u_activation (
    .data_i(acc_next_w),
    .data_o(activated_w)
);

assign atv_data_w = ENABLE_ACTIVATION ? activated_w : acc_next_w;

// result_addr_r ultimately drives the partial-sum BRAM write address. Keep this
// pipeline reset synchronous to avoid asynchronous BRAM control transitions.
always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < 9; i = i + 1) begin
            mul_stage_r[i] <= {MUL_WIDTH{1'b0}};
        end

        mlt_valid_r    <= 1'b0;
        mlt_last_r     <= 1'b0;
        mlt_addr_r     <= {OUTPUT_ADDR_WIDTH{1'b0}};
        mlt_bank_r     <= {BANK_ID_WIDTH{1'b0}};

        at_sum_r       <= {ACC_WIDTH{1'b0}};
        at_valid_r     <= 1'b0;
        at_last_r      <= 1'b0;
        at_addr_r      <= {OUTPUT_ADDR_WIDTH{1'b0}};
        at_bank_r      <= {BANK_ID_WIDTH{1'b0}};

        result_valid_r <= 1'b0;
        result_addr_r  <= {OUTPUT_ADDR_WIDTH{1'b0}};
        result_data_r  <= {ACC_WIDTH{1'b0}};
    end
    else begin
        mlt_valid_r <= mac_en_i;
        mlt_last_r  <= mac_last_i;
        mlt_addr_r  <= output_addr_i;
        mlt_bank_r  <= issue_bank_w;

        if (mac_en_i) begin
            for (i = 0; i < 9; i = i + 1) begin
                mul_stage_r[i] <= mul_lane_w[i];
            end
        end

        at_valid_r <= mlt_valid_r;
        at_last_r  <= mlt_last_r;
        at_addr_r  <= mlt_addr_r;
        at_bank_r  <= mlt_bank_r;

        if (mlt_valid_r) begin
            at_sum_r <= at_sum_w;
        end

        if (!result_valid_r || result_ready_i) begin
            result_valid_r <= at_valid_r && at_last_r;

            if (at_valid_r && at_last_r) begin
                result_addr_r <= at_addr_r;
                result_data_r <= atv_data_w;
            end
        end
    end
end

assign acc_o          = acc_bank_w[issue_bank_w];
assign result_valid_o = result_valid_r;
assign result_addr_o  = result_addr_r;
assign result_o       = result_data_r;
assign busy_o         = mlt_valid_r || at_valid_r || result_valid_r;

endmodule
