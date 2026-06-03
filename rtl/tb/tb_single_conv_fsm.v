`timescale 1ns / 1ps

module tb_single_conv_fsm;

    localparam TB_DATA_WIDTH = 8;
    localparam TB_ACC_WIDTH  = 32;

    localparam TB_IC      = 1;
    localparam TB_OC      = 1;
    localparam TB_IN_H    = 5;
    localparam TB_IN_W    = 5;
    localparam TB_K_H     = 3;
    localparam TB_K_W     = 3;
    localparam TB_STRIDE  = 1;
    localparam TB_PADDING = 0;
    localparam TB_OUT_H   = 3;
    localparam TB_OUT_W   = 3;

    localparam TB_INPUT_SIZE  = TB_IC * TB_IN_H * TB_IN_W;
    localparam TB_WEIGHT_SIZE = TB_OC * TB_IC * TB_K_H * TB_K_W;
    localparam TB_BIAS_SIZE   = TB_OC;
    localparam TB_OUTPUT_SIZE = TB_OC * TB_OUT_H * TB_OUT_W;

    localparam TB_INPUT_ADDR_WIDTH  = (TB_INPUT_SIZE  <= 1) ? 1 : $clog2(TB_INPUT_SIZE);
    localparam TB_WEIGHT_ADDR_WIDTH = (TB_WEIGHT_SIZE <= 1) ? 1 : $clog2(TB_WEIGHT_SIZE);
    localparam TB_BIAS_ADDR_WIDTH   = (TB_BIAS_SIZE   <= 1) ? 1 : $clog2(TB_BIAS_SIZE);
    localparam TB_OUT_ADDR_WIDTH    = (TB_OUTPUT_SIZE <= 1) ? 1 : $clog2(TB_OUTPUT_SIZE);

    localparam TB_MACS_PER_OUTPUT = TB_IC * TB_K_H * TB_K_W;
    localparam TB_TOTAL_MACS      = TB_OUTPUT_SIZE * TB_MACS_PER_OUTPUT;

    reg clk_i;
    reg rst_n;
    reg start_i;

    wire [TB_INPUT_ADDR_WIDTH-1:0]  input_addr_o;
    wire [TB_WEIGHT_ADDR_WIDTH-1:0] weight_addr_o;
    wire [TB_BIAS_ADDR_WIDTH-1:0]   bias_addr_o;
    wire [TB_OUT_ADDR_WIDTH-1:0]    output_addr_o;

    wire busy_o;
    wire done_o;
    wire output_we_o;
    wire mac_en_o;
    wire acc_load_bias_o;

    integer mac_cnt;
    integer output_cnt;
    integer bias_cnt;
    integer err_cnt;

    integer exp_output_idx;
    integer exp_mac_idx;
    integer exp_oc;
    integer exp_oh;
    integer exp_ow;
    integer exp_ic;
    integer exp_kh;
    integer exp_kw;
    integer exp_ih;
    integer exp_iw;
    integer exp_input_addr;
    integer exp_weight_addr;
    integer exp_bias_addr;
    integer rem0;
    integer rem1;

    single_conv_fsm #(
        .DATA_WIDTH (TB_DATA_WIDTH),
        .ACC_WIDTH  (TB_ACC_WIDTH),
        .IC         (TB_IC),
        .OC         (TB_OC),
        .IN_H       (TB_IN_H),
        .IN_W       (TB_IN_W),
        .K_H        (TB_K_H),
        .K_W        (TB_K_W),
        .STRIDE     (TB_STRIDE),
        .PADDING    (TB_PADDING),
        .OUT_H      (TB_OUT_H),
        .OUT_W      (TB_OUT_W)
    ) u_single_conv_fsm (
        .clk_i           (clk_i),
        .rst_n           (rst_n),
        .start_i         (start_i),
        .input_addr_o    (input_addr_o),
        .weight_addr_o   (weight_addr_o),
        .bias_addr_o     (bias_addr_o),
        .output_addr_o   (output_addr_o),
        .busy_o          (busy_o),
        .done_o          (done_o),
        .output_we_o     (output_we_o),
        .mac_en_o        (mac_en_o),
        .acc_load_bias_o (acc_load_bias_o)
    );

    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    initial begin
        mac_cnt    = 0;
        output_cnt = 0;
        bias_cnt   = 0;
        err_cnt    = 0;

        rst_n   = 1'b0;
        start_i = 1'b0;

        repeat (3) @(posedge clk_i);
        rst_n = 1'b1;

        repeat (2) @(posedge clk_i);

        start_i = 1'b1;
        @(posedge clk_i);
        start_i = 1'b0;

        wait (done_o === 1'b1);
        @(negedge clk_i);

        if (mac_cnt != TB_TOTAL_MACS) begin
            $display("[FAIL] MAC count: expected %0d, got %0d", TB_TOTAL_MACS, mac_cnt);
            err_cnt = err_cnt + 1;
        end

        if (output_cnt != TB_OUTPUT_SIZE) begin
            $display("[FAIL] Output write count: expected %0d, got %0d", TB_OUTPUT_SIZE, output_cnt);
            err_cnt = err_cnt + 1;
        end

        if (bias_cnt != TB_OUTPUT_SIZE) begin
            $display("[FAIL] Bias load count: expected %0d, got %0d", TB_OUTPUT_SIZE, bias_cnt);
            err_cnt = err_cnt + 1;
        end

        if (err_cnt == 0)
            $display("[PASS] single_conv_fsm control/address sequence passed.");
        else
            $display("[FAIL] single_conv_fsm failed with %0d errors.", err_cnt);

        repeat (3) @(posedge clk_i);
        $finish;
    end

    always @(negedge clk_i) begin
        if (rst_n) begin
            if (acc_load_bias_o) begin
                exp_bias_addr = bias_cnt / (TB_OUT_H * TB_OUT_W);

                if (bias_addr_o !== exp_bias_addr) begin
                    $display("[FAIL] bias_addr mismatch at bias_cnt=%0d: expected %0d, got %0d",
                             bias_cnt, exp_bias_addr, bias_addr_o);
                    err_cnt = err_cnt + 1;
                end

                bias_cnt = bias_cnt + 1;
            end

            if (mac_en_o) begin
                exp_output_idx = mac_cnt / TB_MACS_PER_OUTPUT;
                exp_mac_idx    = mac_cnt % TB_MACS_PER_OUTPUT;

                exp_oc = exp_output_idx / (TB_OUT_H * TB_OUT_W);
                rem0   = exp_output_idx % (TB_OUT_H * TB_OUT_W);
                exp_oh = rem0 / TB_OUT_W;
                exp_ow = rem0 % TB_OUT_W;

                exp_ic = exp_mac_idx / (TB_K_H * TB_K_W);
                rem1   = exp_mac_idx % (TB_K_H * TB_K_W);
                exp_kh = rem1 / TB_K_W;
                exp_kw = rem1 % TB_K_W;

                exp_ih = exp_oh * TB_STRIDE + exp_kh - TB_PADDING;
                exp_iw = exp_ow * TB_STRIDE + exp_kw - TB_PADDING;

                exp_input_addr  = exp_ic * TB_IN_H * TB_IN_W
                                + exp_ih * TB_IN_W
                                + exp_iw;

                exp_weight_addr = exp_oc * TB_IC * TB_K_H * TB_K_W
                                + exp_ic * TB_K_H * TB_K_W
                                + exp_kh * TB_K_W
                                + exp_kw;

                if (input_addr_o !== exp_input_addr) begin
                    $display("[FAIL] input_addr mismatch at mac_cnt=%0d: expected %0d, got %0d",
                             mac_cnt, exp_input_addr, input_addr_o);
                    err_cnt = err_cnt + 1;
                end

                if (weight_addr_o !== exp_weight_addr) begin
                    $display("[FAIL] weight_addr mismatch at mac_cnt=%0d: expected %0d, got %0d",
                             mac_cnt, exp_weight_addr, weight_addr_o);
                    err_cnt = err_cnt + 1;
                end

                mac_cnt = mac_cnt + 1;
            end

            if (output_we_o) begin
                if (output_addr_o !== output_cnt) begin
                    $display("[FAIL] output_addr mismatch at output_cnt=%0d: expected %0d, got %0d",
                             output_cnt, output_cnt, output_addr_o);
                    err_cnt = err_cnt + 1;
                end

                output_cnt = output_cnt + 1;
            end
        end
    end

endmodule
