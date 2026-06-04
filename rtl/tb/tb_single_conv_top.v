`timescale 1ns/1ps

module tb_single_conv_top;
    localparam DATA_WIDTH = 8;
    localparam MUL_WIDTH  = 16;
    localparam ACC_WIDTH  = 32;
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
    reg signed [DATA_WIDTH-1:0] input_data_i;
    reg signed [DATA_WIDTH-1:0] weight_data_i;
    reg signed [ACC_WIDTH-1:0] bias_data_i;

    wire [INPUT_ADDR_WIDTH-1:0] input_addr_o;
    wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr_o;
    wire [OUTPUT_ADDR_WIDTH-1:0] output_addr_o;
    wire output_we_o;
    wire busy_o;
    wire done_o;
    wire signed [ACC_WIDTH-1:0] output_data_o;

    reg signed [7:0] input_mem [0:24];
    reg signed [7:0] weight_mem [0:8];
    reg signed [ACC_WIDTH-1:0] bias_mem [0:0];
    reg signed [ACC_WIDTH-1:0] expected_mem [0:8];

    integer fd;
    integer code;
    integer value;
    integer count;
    integer write_count;
    integer done_seen;
    integer cycles;

    top_single_conv #(
        .DATA_WIDTH(DATA_WIDTH),
        .MUL_WIDTH(MUL_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
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
        .input_data_i(input_data_i),
        .weight_data_i(weight_data_i),
        .bias_data_i(bias_data_i),
        .input_addr_o(input_addr_o),
        .weight_addr_o(weight_addr_o),
        .output_addr_o(output_addr_o),
        .output_we_o(output_we_o),
        .busy_o(busy_o),
        .done_o(done_o),
        .output_data_o(output_data_o)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    always @(*) begin
        input_data_i = input_mem[input_addr_o];
        weight_data_i = weight_mem[weight_addr_o];
        bias_data_i = bias_mem[0];
    end

    task load_input;
        begin
            count = 0;
            fd = $fopen("D:/a.Projects/cnn_accelerator/CNN_YOLO_AI_accelerator/sw/fixture/single_conv_001/input_int8.hex", "r");
            if (fd == 0) begin $display("FAIL: cannot open input"); $finish; end
            while (!$feof(fd)) begin
                code = $fscanf(fd, "%d\n", value);
                if (code == 1) begin input_mem[count] = value; count = count + 1; end
            end
            $fclose(fd);
        end
    endtask

    task load_weight;
        begin
            count = 0;
            fd = $fopen("D:/a.Projects/cnn_accelerator/CNN_YOLO_AI_accelerator/sw/fixture/single_conv_001/weight_int8.hex", "r");
            if (fd == 0) begin $display("FAIL: cannot open weight"); $finish; end
            while (!$feof(fd)) begin
                code = $fscanf(fd, "%d\n", value);
                if (code == 1) begin weight_mem[count] = value; count = count + 1; end
            end
            $fclose(fd);
        end
    endtask

    task load_bias;
        begin
            count = 0;
            fd = $fopen("D:/a.Projects/cnn_accelerator/CNN_YOLO_AI_accelerator/sw/fixture/single_conv_001/bias_int32.hex", "r");
            if (fd == 0) begin $display("FAIL: cannot open bias"); $finish; end
            while (!$feof(fd)) begin
                code = $fscanf(fd, "%d\n", value);
                if (code == 1) begin bias_mem[count] = value; count = count + 1; end
            end
            $fclose(fd);
        end
    endtask

    task load_expected;
        begin
            count = 0;
            fd = $fopen("D:/a.Projects/cnn_accelerator/CNN_YOLO_AI_accelerator/sw/fixture/single_conv_001/expected_acc_int32.hex", "r");
            if (fd == 0) begin $display("FAIL: cannot open expected"); $finish; end
            while (!$feof(fd)) begin
                code = $fscanf(fd, "%d\n", value);
                if (code == 1) begin expected_mem[count] = value; count = count + 1; end
            end
            $fclose(fd);
        end
    endtask

    initial begin
        load_input();
        load_weight();
        load_bias();
        load_expected();

        start_i = 1'b0;
        write_count = 0;
        done_seen = 0;
        cycles = 0;

        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        start_i = 1'b1;
        @(posedge clk);
        start_i = 1'b0;

        while (done_seen == 0 && cycles < 200) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;

            if (output_we_o) begin
                if (output_data_o !== expected_mem[output_addr_o]) begin
                    $display("FAIL: output_addr=%0d got=%0d expected=%0d",
                             output_addr_o, output_data_o, expected_mem[output_addr_o]);
                    $finish;
                end
                write_count = write_count + 1;
            end

            if (done_o)
                done_seen = 1;
        end

        if (cycles >= 200) begin
            $display("FAIL: timeout waiting for done_o");
            $finish;
        end
        if (write_count != OUTPUT_W * OUTPUT_H) begin
            $display("FAIL: write_count=%0d expected=%0d", write_count, OUTPUT_W * OUTPUT_H);
            $finish;
        end

        $display("PASS: tb_single_conv_top");
        $finish;
    end
endmodule
