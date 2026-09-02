`timescale 1ns/1ps

// Fused YOLOv3-Tiny activation and INT32-to-INT8 requantization stream.
// MODE_LINEAR applies the positive coefficient to both signs.
// MODE_LEAKY_RELU selects the fused negative coefficient when acc_i < 0.
// Rounding is nearest with exact halves away from zero. Reserved modes are
// calculated as LINEAR and assert mode_error_o.
module activation_requant_int8_stream #(
    parameter ACC_WIDTH = 32,
    parameter MULT_WIDTH = 32,
    parameter SHIFT_WIDTH = 6,
    parameter ZERO_POINT_WIDTH = 32,
    parameter TAG_WIDTH = 10
)(
    input wire clk,
    input wire rst_n,
    input wire signed [ACC_WIDTH-1:0] acc_i,
    input wire [1:0] activation_mode_i,
    input wire signed [MULT_WIDTH-1:0] multiplier_pos_i,
    input wire [SHIFT_WIDTH-1:0] shift_pos_i,
    input wire signed [MULT_WIDTH-1:0] multiplier_neg_i,
    input wire [SHIFT_WIDTH-1:0] shift_neg_i,
    input wire signed [ZERO_POINT_WIDTH-1:0] zero_point_i,
    input wire [TAG_WIDTH-1:0] tag_i,
    input wire last_i,
    input wire valid_i,
    output wire ready_o,
    output wire signed [7:0] data_o,
    output wire clipped_o,
    output wire mode_error_o,
    output wire [TAG_WIDTH-1:0] tag_o,
    output wire last_o,
    output wire valid_o,
    input wire ready_i
);

localparam [1:0] MODE_LINEAR = 2'b00;
localparam [1:0] MODE_LEAKY_RELU = 2'b01;

reg signed [ACC_WIDTH-1:0] s0_acc_r;
reg signed [MULT_WIDTH-1:0] s0_multiplier_r;
reg [SHIFT_WIDTH-1:0] s0_shift_r;
reg signed [ZERO_POINT_WIDTH-1:0] s0_zero_point_r;
reg [TAG_WIDTH-1:0] s0_tag_r;
reg s0_last_r, s0_mode_error_r, s0_valid_r;

reg signed [63:0] s1_product_r;
reg [SHIFT_WIDTH-1:0] s1_shift_r;
reg signed [ZERO_POINT_WIDTH-1:0] s1_zero_point_r;
reg [TAG_WIDTH-1:0] s1_tag_r;
reg s1_last_r, s1_mode_error_r, s1_valid_r;

reg [64:0] s2_magnitude_r;
reg [SHIFT_WIDTH-1:0] s2_shift_r;
reg signed [ZERO_POINT_WIDTH-1:0] s2_zero_point_r;
reg [TAG_WIDTH-1:0] s2_tag_r;
reg s2_negative_r, s2_last_r, s2_mode_error_r, s2_valid_r;

reg [64:0] s3_rounded_magnitude_r;
reg [SHIFT_WIDTH-1:0] s3_shift_r;
reg signed [ZERO_POINT_WIDTH-1:0] s3_zero_point_r;
reg [TAG_WIDTH-1:0] s3_tag_r;
reg s3_negative_r, s3_last_r, s3_mode_error_r, s3_valid_r;

reg [64:0] s4_shifted_magnitude_r;
reg signed [ZERO_POINT_WIDTH-1:0] s4_zero_point_r;
reg [TAG_WIDTH-1:0] s4_tag_r;
reg s4_negative_r, s4_last_r, s4_mode_error_r, s4_valid_r;

reg signed [64:0] s5_scaled_r;
reg signed [ZERO_POINT_WIDTH-1:0] s5_zero_point_r;
reg [TAG_WIDTH-1:0] s5_tag_r;
reg s5_last_r, s5_mode_error_r, s5_valid_r;

reg signed [7:0] s6_data_r;
reg [TAG_WIDTH-1:0] s6_tag_r;
reg s6_clipped_r, s6_mode_error_r, s6_last_r, s6_valid_r;

wire pipeline_advance_w;
wire [64:0] rounding_bias_w;
wire signed [65:0] shifted_wide_w;

// A downstream stall freezes all stages. With no stall, II=1.
assign pipeline_advance_w = !s6_valid_r || ready_i;
assign ready_o = pipeline_advance_w;
assign rounding_bias_w = (s2_shift_r == 0) ? 65'd0 :
                         (65'd1 << (s2_shift_r - 1'b1));
assign shifted_wide_w =
    $signed({s5_scaled_r[64], s5_scaled_r}) +
    $signed({{(66-ZERO_POINT_WIDTH){s5_zero_point_r[ZERO_POINT_WIDTH-1]}},
             s5_zero_point_r});

assign data_o = s6_data_r;
assign clipped_o = s6_clipped_r;
assign mode_error_o = s6_mode_error_r;
assign tag_o = s6_tag_r;
assign last_o = s6_last_r;
assign valid_o = s6_valid_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s0_acc_r <= 0; s0_multiplier_r <= 0; s0_shift_r <= 0;
        s0_zero_point_r <= 0; s0_tag_r <= 0; s0_last_r <= 0;
        s0_mode_error_r <= 0; s0_valid_r <= 0;
        s1_product_r <= 0; s1_shift_r <= 0; s1_zero_point_r <= 0;
        s1_tag_r <= 0; s1_last_r <= 0; s1_mode_error_r <= 0; s1_valid_r <= 0;
        s2_magnitude_r <= 0; s2_negative_r <= 0; s2_shift_r <= 0;
        s2_zero_point_r <= 0; s2_tag_r <= 0; s2_last_r <= 0;
        s2_mode_error_r <= 0; s2_valid_r <= 0;
        s3_rounded_magnitude_r <= 0; s3_negative_r <= 0; s3_shift_r <= 0;
        s3_zero_point_r <= 0; s3_tag_r <= 0; s3_last_r <= 0;
        s3_mode_error_r <= 0; s3_valid_r <= 0;
        s4_shifted_magnitude_r <= 0; s4_negative_r <= 0;
        s4_zero_point_r <= 0; s4_tag_r <= 0; s4_last_r <= 0;
        s4_mode_error_r <= 0; s4_valid_r <= 0;
        s5_scaled_r <= 0; s5_zero_point_r <= 0; s5_tag_r <= 0;
        s5_last_r <= 0; s5_mode_error_r <= 0; s5_valid_r <= 0;
        s6_data_r <= 0; s6_clipped_r <= 0; s6_mode_error_r <= 0;
        s6_tag_r <= 0; s6_last_r <= 0; s6_valid_r <= 0;
    end
    else if (pipeline_advance_w) begin
        // Stage 6: zero point and INT8 saturation.
        s6_valid_r <= s5_valid_r;
        s6_tag_r <= s5_tag_r;
        s6_last_r <= s5_last_r;
        s6_mode_error_r <= s5_mode_error_r;
        if (s5_valid_r) begin
            if (shifted_wide_w > 66'sd127) begin
                s6_data_r <= 8'sd127;
                s6_clipped_r <= 1'b1;
            end
            else if (shifted_wide_w < -66'sd128) begin
                s6_data_r <= -8'sd128;
                s6_clipped_r <= 1'b1;
            end
            else begin
                s6_data_r <= shifted_wide_w[7:0];
                s6_clipped_r <= 1'b0;
            end
        end

        // Stage 5: restore product sign.
        s5_valid_r <= s4_valid_r;
        s5_zero_point_r <= s4_zero_point_r;
        s5_tag_r <= s4_tag_r;
        s5_last_r <= s4_last_r;
        s5_mode_error_r <= s4_mode_error_r;
        if (s4_valid_r) begin
            s5_scaled_r <= s4_negative_r ?
                           -$signed(s4_shifted_magnitude_r) :
                           $signed(s4_shifted_magnitude_r);
        end

        // Stage 4: variable right shift.
        s4_valid_r <= s3_valid_r;
        s4_negative_r <= s3_negative_r;
        s4_zero_point_r <= s3_zero_point_r;
        s4_tag_r <= s3_tag_r;
        s4_last_r <= s3_last_r;
        s4_mode_error_r <= s3_mode_error_r;
        if (s3_valid_r)
            s4_shifted_magnitude_r <= s3_rounded_magnitude_r >> s3_shift_r;

        // Stage 3: add round-to-nearest bias.
        s3_valid_r <= s2_valid_r;
        s3_negative_r <= s2_negative_r;
        s3_shift_r <= s2_shift_r;
        s3_zero_point_r <= s2_zero_point_r;
        s3_tag_r <= s2_tag_r;
        s3_last_r <= s2_last_r;
        s3_mode_error_r <= s2_mode_error_r;
        if (s2_valid_r)
            s3_rounded_magnitude_r <= s2_magnitude_r + rounding_bias_w;

        // Stage 2: signed product to sign and magnitude.
        s2_valid_r <= s1_valid_r;
        s2_negative_r <= s1_product_r[63];
        s2_shift_r <= s1_shift_r;
        s2_zero_point_r <= s1_zero_point_r;
        s2_tag_r <= s1_tag_r;
        s2_last_r <= s1_last_r;
        s2_mode_error_r <= s1_mode_error_r;
        if (s1_valid_r)
            s2_magnitude_r <= s1_product_r[63] ?
                              ({1'b0, ~s1_product_r} + 65'd1) :
                              {1'b0, s1_product_r};

        // Stage 1: the one shared signed multiplier.
        s1_valid_r <= s0_valid_r;
        s1_shift_r <= s0_shift_r;
        s1_zero_point_r <= s0_zero_point_r;
        s1_tag_r <= s0_tag_r;
        s1_last_r <= s0_last_r;
        s1_mode_error_r <= s0_mode_error_r;
        if (s0_valid_r)
            s1_product_r <= $signed(s0_acc_r) * $signed(s0_multiplier_r);

        // Stage 0: sample transaction and select LINEAR/LEAKY coefficient.
        s0_valid_r <= valid_i;
        s0_acc_r <= acc_i;
        s0_zero_point_r <= zero_point_i;
        s0_tag_r <= tag_i;
        s0_last_r <= last_i;
        s0_mode_error_r <= (activation_mode_i != MODE_LINEAR) &&
                           (activation_mode_i != MODE_LEAKY_RELU);
        if ((activation_mode_i == MODE_LEAKY_RELU) && acc_i[ACC_WIDTH-1]) begin
            s0_multiplier_r <= multiplier_neg_i;
            s0_shift_r <= shift_neg_i;
        end
        else begin
            s0_multiplier_r <= multiplier_pos_i;
            s0_shift_r <= shift_pos_i;
        end
    end
end

endmodule
