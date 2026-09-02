`timescale 1ns/1ps

module tb_activation_requant_int8_stream;

localparam TAG_WIDTH = 10;
localparam MODE_LINEAR = 2'b00;
localparam MODE_LEAKY_RELU = 2'b01;
localparam MAX_VECTORS = 1200;

reg clk;
reg rst_n;
reg signed [31:0] acc_i;
reg [1:0] activation_mode_i;
reg signed [31:0] multiplier_pos_i;
reg [5:0] shift_pos_i;
reg signed [31:0] multiplier_neg_i;
reg [5:0] shift_neg_i;
reg signed [31:0] zero_point_i;
reg [TAG_WIDTH-1:0] tag_i;
reg last_i;
reg valid_i;
wire ready_o;

wire signed [7:0] data_o;
wire clipped_o;
wire mode_error_o;
wire [TAG_WIDTH-1:0] tag_o;
wire last_o;
wire valid_o;
reg ready_i;

reg signed [7:0] expected_data [0:MAX_VECTORS-1];
reg expected_clipped [0:MAX_VECTORS-1];
reg expected_mode_error [0:MAX_VECTORS-1];
reg [TAG_WIDTH-1:0] expected_tag [0:MAX_VECTORS-1];
reg expected_last [0:MAX_VECTORS-1];

integer expected_count;
integer checked_count;
integer random_seed;
integer i;
integer cycles;
reg random_stall_enable;

reg hold_active;
reg signed [7:0] held_data;
reg held_clipped;
reg held_mode_error;
reg [TAG_WIDTH-1:0] held_tag;
reg held_last;

activation_requant_int8_stream #(
    .TAG_WIDTH(TAG_WIDTH)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .acc_i(acc_i),
    .activation_mode_i(activation_mode_i),
    .multiplier_pos_i(multiplier_pos_i),
    .shift_pos_i(shift_pos_i),
    .multiplier_neg_i(multiplier_neg_i),
    .shift_neg_i(shift_neg_i),
    .zero_point_i(zero_point_i),
    .tag_i(tag_i),
    .last_i(last_i),
    .valid_i(valid_i),
    .ready_o(ready_o),
    .data_o(data_o),
    .clipped_o(clipped_o),
    .mode_error_o(mode_error_o),
    .tag_o(tag_o),
    .last_o(last_o),
    .valid_o(valid_o),
    .ready_i(ready_i)
);

initial clk = 1'b0;
always #5 clk = ~clk;

// Exercise long and irregular downstream stalls.
always @(negedge clk) begin
    if (!rst_n) begin
        ready_i <= 1'b0;
    end
    else if (random_stall_enable) begin
        ready_i <= (($random(random_seed) & 32'h7) != 0);
    end
    else begin
        ready_i <= 1'b1;
    end
end

task queue_expected;
    input signed [31:0] acc;
    input [1:0] mode;
    input signed [31:0] m_pos;
    input [5:0] s_pos;
    input signed [31:0] m_neg;
    input [5:0] s_neg;
    input signed [31:0] zp;
    input [TAG_WIDTH-1:0] tag;
    input last;
    reg signed [31:0] selected_multiplier;
    reg [5:0] selected_shift;
    reg signed [63:0] product;
    reg [64:0] magnitude;
    reg [64:0] rounded_magnitude;
    reg signed [64:0] scaled;
    reg signed [65:0] shifted;
    begin
        if ((mode == MODE_LEAKY_RELU) && acc[31]) begin
            selected_multiplier = m_neg;
            selected_shift = s_neg;
        end
        else begin
            selected_multiplier = m_pos;
            selected_shift = s_pos;
        end

        product = acc * selected_multiplier;
        if (selected_shift == 0) begin
            scaled = {product[63], product};
        end
        else begin
            magnitude = product[63] ? ({1'b0, ~product} + 65'd1) :
                                      {1'b0, product};
            rounded_magnitude =
                (magnitude + (65'd1 << (selected_shift - 1'b1))) >>
                selected_shift;
            scaled = product[63] ? -$signed(rounded_magnitude) :
                                   $signed(rounded_magnitude);
        end

        shifted = $signed({scaled[64], scaled}) +
                  $signed({{34{zp[31]}}, zp});

        if (shifted > 66'sd127) begin
            expected_data[expected_count] = 8'sd127;
            expected_clipped[expected_count] = 1'b1;
        end
        else if (shifted < -66'sd128) begin
            expected_data[expected_count] = -8'sd128;
            expected_clipped[expected_count] = 1'b1;
        end
        else begin
            expected_data[expected_count] = shifted[7:0];
            expected_clipped[expected_count] = 1'b0;
        end

        expected_mode_error[expected_count] =
            (mode != MODE_LINEAR) && (mode != MODE_LEAKY_RELU);
        expected_tag[expected_count] = tag;
        expected_last[expected_count] = last;
        expected_count = expected_count + 1;
    end
endtask

task send_transaction;
    input signed [31:0] acc;
    input [1:0] mode;
    input signed [31:0] m_pos;
    input [5:0] s_pos;
    input signed [31:0] m_neg;
    input [5:0] s_neg;
    input signed [31:0] zp;
    input [TAG_WIDTH-1:0] tag;
    input last;
    begin
        queue_expected(acc, mode, m_pos, s_pos, m_neg, s_neg, zp, tag, last);
        @(negedge clk);
        acc_i = acc;
        activation_mode_i = mode;
        multiplier_pos_i = m_pos;
        shift_pos_i = s_pos;
        multiplier_neg_i = m_neg;
        shift_neg_i = s_neg;
        zero_point_i = zp;
        tag_i = tag;
        last_i = last;
        valid_i = 1'b1;

        // A transaction is accepted on a positive edge with valid && ready.
        // Waiting on negedges can race the randomized ready_i driver and can
        // accidentally leave valid asserted for a second acceptance.
        @(posedge clk);
        while (!ready_o) begin
            @(posedge clk);
        end
        @(negedge clk);
        valid_i = 1'b0;
    end
endtask

// Scoreboard and ready/valid stability checks use values sampled before the
// DUT nonblocking assignments at each active edge.
always @(posedge clk) begin
    if (!rst_n) begin
        checked_count = 0;
        hold_active = 1'b0;
    end
    else begin
        if (hold_active) begin
            if ((data_o !== held_data) ||
                (clipped_o !== held_clipped) ||
                (mode_error_o !== held_mode_error) ||
                (tag_o !== held_tag) ||
                (last_o !== held_last) ||
                !valid_o) begin
                $display("FAIL: output payload changed during stall");
                $finish;
            end
        end

        if (valid_o && ready_i) begin
            if (checked_count >= expected_count) begin
                $display("FAIL: unexpected output transaction");
                $finish;
            end
            if ((data_o !== expected_data[checked_count]) ||
                (clipped_o !== expected_clipped[checked_count]) ||
                (mode_error_o !== expected_mode_error[checked_count]) ||
                (tag_o !== expected_tag[checked_count]) ||
                (last_o !== expected_last[checked_count])) begin
                $display("FAIL: index=%0d data=%0d/%0d clip=%0b/%0b mode_error=%0b/%0b tag=%0d/%0d last=%0b/%0b",
                         checked_count,
                         data_o, expected_data[checked_count],
                         clipped_o, expected_clipped[checked_count],
                         mode_error_o, expected_mode_error[checked_count],
                         tag_o, expected_tag[checked_count],
                         last_o, expected_last[checked_count]);
                $finish;
            end
            checked_count = checked_count + 1;
        end

        hold_active = valid_o && !ready_i;
        if (valid_o && !ready_i) begin
            held_data = data_o;
            held_clipped = clipped_o;
            held_mode_error = mode_error_o;
            held_tag = tag_o;
            held_last = last_o;
        end
    end
end

initial begin
    rst_n = 1'b0;
    acc_i = 32'sd0;
    activation_mode_i = MODE_LINEAR;
    multiplier_pos_i = 32'sd0;
    shift_pos_i = 6'd0;
    multiplier_neg_i = 32'sd0;
    shift_neg_i = 6'd0;
    zero_point_i = 32'sd0;
    tag_i = {TAG_WIDTH{1'b0}};
    last_i = 1'b0;
    valid_i = 1'b0;
    ready_i = 1'b0;
    random_stall_enable = 1'b0;
    expected_count = 0;
    checked_count = 0;
    random_seed = 32'h26082026;
    cycles = 0;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    // LINEAR uses the positive coefficient for both input signs.
    send_transaction(32'sd10, MODE_LINEAR, 32'sd1, 6'd0,
                     32'sd99, 6'd0, 32'sd0, 10'd1, 1'b0);
    send_transaction(-32'sd10, MODE_LINEAR, 32'sd1, 6'd0,
                     32'sd99, 6'd0, 32'sd0, 10'd2, 1'b0);

    // LEAKY_RELU bypasses the negative coefficient for positive inputs and
    // uses it for negative inputs.  -3/2 is the exact-half rounding case.
    send_transaction(32'sd10, MODE_LEAKY_RELU, 32'sd1, 6'd0,
                     32'sd1, 6'd1, 32'sd0, 10'd3, 1'b0);
    send_transaction(-32'sd3, MODE_LEAKY_RELU, 32'sd1, 6'd0,
                     32'sd1, 6'd1, 32'sd0, 10'd4, 1'b0);
    send_transaction(-32'sd100, MODE_LEAKY_RELU, 32'sd1, 6'd0,
                     32'sd3277, 6'd15, 32'sd0, 10'd5, 1'b0);

    // Zero point and both saturation boundaries.
    send_transaction(32'sd10, MODE_LINEAR, 32'sd1, 6'd1,
                     32'sd0, 6'd0, 32'sd3, 10'd6, 1'b0);
    send_transaction(32'sd1000, MODE_LINEAR, 32'sd1, 6'd0,
                     32'sd0, 6'd0, 32'sd0, 10'd7, 1'b0);
    send_transaction(-32'sd1000, MODE_LINEAR, 32'sd1, 6'd0,
                     32'sd0, 6'd0, 32'sd0, 10'd8, 1'b0);

    // shift=63, INT32_MIN, and reserved-mode fallback/error behavior.
    send_transaction(-32'sh80000000, MODE_LEAKY_RELU, 32'sd1, 6'd0,
                     32'sd1, 6'd63, 32'sd0, 10'd9, 1'b0);
    send_transaction(-32'sd20, 2'b10, 32'sd1, 6'd1,
                     32'sd999, 6'd0, 32'sd0, 10'd10, 1'b1);

    random_stall_enable = 1'b1;
    for (i = 0; i < 1000; i = i + 1) begin
        send_transaction($random(random_seed),
                         $random(random_seed) & 2'b11,
                         $random(random_seed) & 32'h000fffff,
                         $random(random_seed) & 6'h3f,
                         $random(random_seed) & 32'h000fffff,
                         $random(random_seed) & 6'h3f,
                         ($random(random_seed) % 512) - 256,
                         i[TAG_WIDTH-1:0],
                         i == 999);
    end

    valid_i = 1'b0;
    while ((checked_count != expected_count) && (cycles < 100000)) begin
        @(posedge clk);
        cycles = cycles + 1;
    end

    if (checked_count != expected_count) begin
        $display("FAIL: timeout checked=%0d expected=%0d",
                 checked_count, expected_count);
        $finish;
    end

    $display("PASS: tb_activation_requant_int8_stream directed=10 random=1000 stalls=enabled");
    $finish;
end

endmodule
