`timescale 1ns/1ps

module tb_single_conv_control;
    localparam INPUT_W = 5;
    localparam INPUT_H = 5;
    localparam KERNEL = 3;
    localparam OUTPUT_W = 3;
    localparam OUTPUT_H = 3;
    localparam INPUT_ADDR_WIDTH = 5;
    localparam WEIGHT_ADDR_WIDTH = 4;
    localparam OUTPUT_ADDR_WIDTH = 4;
    localparam OUT_POS_WIDTH = 2;
    localparam K_POS_WIDTH = 2;

    reg clk;
    reg rst_n;
    reg start_i;

    wire busy_o;
    wire done_o;
    wire acc_clear_o;
    wire acc_load_bias_o;
    wire mac_en_o;
    wire output_we_o;
    wire [INPUT_ADDR_WIDTH-1:0] input_addr_o;
    wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr_o;
    wire [OUTPUT_ADDR_WIDTH-1:0] output_addr_o;

    integer mac_count;
    integer load_bias_count;
    integer write_count;
    integer done_count;
    integer exp_oh;
    integer exp_ow;
    integer exp_kh;
    integer exp_kw;
    integer exp_input_addr;
    integer exp_weight_addr;
    integer exp_output_addr;
    integer cycles;

    single_conv_control #(
        .INPUT_W(INPUT_W),
        .INPUT_H(INPUT_H),
        .KERNEL(KERNEL),
        .OUTPUT_W(OUTPUT_W),
        .OUTPUT_H(OUTPUT_H),
        .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
        .OUTPUT_ADDR_WIDTH(OUTPUT_ADDR_WIDTH),
        .OUT_POS_WIDTH(OUT_POS_WIDTH),
        .K_POS_WIDTH(K_POS_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_i(start_i),
        .busy_o(busy_o),
        .done_o(done_o),
        .acc_clear_o(acc_clear_o),
        .acc_load_bias_o(acc_load_bias_o),
        .mac_en_o(mac_en_o),
        .output_we_o(output_we_o),
        .input_addr_o(input_addr_o),
        .weight_addr_o(weight_addr_o),
        .output_addr_o(output_addr_o)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task fail;
        input [255:0] msg;
        begin
            $display("FAIL: %0s", msg);
            $finish;
        end
    endtask

    task sample_outputs;
        begin
            if (acc_clear_o !== 1'b0)
                fail("acc_clear_o should stay low in this controller");

            if (acc_load_bias_o) begin
                exp_output_addr = load_bias_count;
                if (output_addr_o !== exp_output_addr[OUTPUT_ADDR_WIDTH-1:0])
                    fail("wrong output_addr during LOAD_BIAS");
                load_bias_count = load_bias_count + 1;
            end

            if (mac_en_o) begin
                exp_oh = mac_count / (OUTPUT_W * KERNEL * KERNEL);
                exp_ow = (mac_count / (KERNEL * KERNEL)) % OUTPUT_W;
                exp_kh = (mac_count / KERNEL) % KERNEL;
                exp_kw = mac_count % KERNEL;
                exp_input_addr = (exp_oh + exp_kh) * INPUT_W + (exp_ow + exp_kw);
                exp_weight_addr = exp_kh * KERNEL + exp_kw;

                if (input_addr_o !== exp_input_addr[INPUT_ADDR_WIDTH-1:0])
                    fail("wrong input_addr during MAC");
                if (weight_addr_o !== exp_weight_addr[WEIGHT_ADDR_WIDTH-1:0])
                    fail("wrong weight_addr during MAC");

                mac_count = mac_count + 1;
            end

            if (output_we_o) begin
                exp_output_addr = write_count;
                if (output_addr_o !== exp_output_addr[OUTPUT_ADDR_WIDTH-1:0])
                    fail("wrong output_addr during WRITE_OUT");
                write_count = write_count + 1;
            end

            if (done_o) begin
                done_count = done_count + 1;
            end
        end
    endtask

    initial begin
        start_i = 1'b0;
        mac_count = 0;
        load_bias_count = 0;
        write_count = 0;
        done_count = 0;
        cycles = 0;

        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        start_i = 1'b1;
        @(posedge clk);
        start_i = 1'b0;
        #1;
        sample_outputs();

        while (done_count == 0 && cycles < 200) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
            sample_outputs();
        end

        if (cycles >= 200) fail("timeout waiting for done_o");
        if (load_bias_count != OUTPUT_W * OUTPUT_H) fail("wrong load_bias count");
        if (mac_count != OUTPUT_W * OUTPUT_H * KERNEL * KERNEL) fail("wrong mac count");
        if (write_count != OUTPUT_W * OUTPUT_H) fail("wrong output write count");
        if (done_count != 1) fail("wrong done count");

        @(posedge clk);
        #1;
        if (busy_o !== 1'b0) fail("busy_o should deassert after DONE");

        $display("PASS: tb_single_conv_control");
        $finish;
    end
endmodule
