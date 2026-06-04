`timescale 1ns/1ps

module tb_acc;
    localparam IN_WIDTH  = 16;
    localparam ACC_WIDTH = 32;

    localparam INPUT_SIZE  = 25;
    localparam WEIGHT_SIZE = 9;

    reg clk;
    reg rst_n;
    reg clear_i;
    reg load_bias_i;
    reg en_i;
    reg signed [IN_WIDTH-1:0] data_i;
    reg signed [ACC_WIDTH-1:0] bias_i;
    wire signed [ACC_WIDTH-1:0] acc_o;

    reg signed [7:0] input_mem [0:INPUT_SIZE-1];
    reg signed [7:0] weight_mem [0:WEIGHT_SIZE-1];
    reg signed [ACC_WIDTH-1:0] bias_mem [0:0];
    reg signed [ACC_WIDTH-1:0] expected_mem [0:8];

    integer fd;
    integer code;
    integer value;
    integer i;
    integer calc;
    integer input_idx [0:8];

    acc #(
        .IN_WIDTH(IN_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear_i(clear_i),
        .load_bias_i(load_bias_i),
        .en_i(en_i),
        .data_i(data_i),
        .bias_i(bias_i),
        .acc_o(acc_o)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task load_i8_file;
        input [1023:0] path;
        output integer count;
        begin
            count = 0;
            fd = $fopen(path, "r");
            if (fd == 0) begin
                $display("FAIL: cannot open %0s", path);
                $finish;
            end
            while (!$feof(fd)) begin
                code = $fscanf(fd, "%d\n", value);
                if (code == 1) begin
                    if (path == "D:/a.Projects/cnn_accelerator/CNN_YOLO_AI_accelerator/sw/fixture/single_conv_001/input_int8.hex")
                        input_mem[count] = value;
                    else
                        weight_mem[count] = value;
                    count = count + 1;
                end
            end
            $fclose(fd);
        end
    endtask

    task load_i32_file;
        input [1023:0] path;
        output integer count;
        begin
            count = 0;
            fd = $fopen(path, "r");
            if (fd == 0) begin
                $display("FAIL: cannot open %0s", path);
                $finish;
            end
            while (!$feof(fd)) begin
                code = $fscanf(fd, "%d\n", value);
                if (code == 1) begin
                    if (path == "D:/a.Projects/cnn_accelerator/CNN_YOLO_AI_accelerator/sw/fixture/single_conv_001/bias_int32.hex")
                        bias_mem[count] = value;
                    else
                        expected_mem[count] = value;
                    count = count + 1;
                end
            end
            $fclose(fd);
        end
    endtask

    task check_equal;
        input signed [ACC_WIDTH-1:0] got;
        input signed [ACC_WIDTH-1:0] exp;
        input [255:0] name;
        begin
            if (got !== exp) begin
                $display("FAIL: %0s got=%0d expected=%0d", name, got, exp);
                $finish;
            end
        end
    endtask

    initial begin
        clear_i = 1'b0;
        load_bias_i = 1'b0;
        en_i = 1'b0;
        data_i = 0;
        bias_i = 0;
        calc = 0;

        load_i8_file("D:/a.Projects/cnn_accelerator/CNN_YOLO_AI_accelerator/sw/fixture/single_conv_001/input_int8.hex", calc);
        if (calc != INPUT_SIZE) begin
            $display("FAIL: input count=%0d", calc);
            $finish;
        end

        load_i8_file("D:/a.Projects/cnn_accelerator/CNN_YOLO_AI_accelerator/sw/fixture/single_conv_001/weight_int8.hex", calc);
        if (calc != WEIGHT_SIZE) begin
            $display("FAIL: weight count=%0d", calc);
            $finish;
        end

        load_i32_file("D:/a.Projects/cnn_accelerator/CNN_YOLO_AI_accelerator/sw/fixture/single_conv_001/bias_int32.hex", calc);
        if (calc != 1) begin
            $display("FAIL: bias count=%0d", calc);
            $finish;
        end

        load_i32_file("D:/a.Projects/cnn_accelerator/CNN_YOLO_AI_accelerator/sw/fixture/single_conv_001/expected_acc_int32.hex", calc);
        if (calc != 9) begin
            $display("FAIL: expected count=%0d", calc);
            $finish;
        end

        input_idx[0] = 0;  input_idx[1] = 1;  input_idx[2] = 2;
        input_idx[3] = 5;  input_idx[4] = 6;  input_idx[5] = 7;
        input_idx[6] = 10; input_idx[7] = 11; input_idx[8] = 12;

        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1 check_equal(acc_o, 0, "reset");

        bias_i = bias_mem[0];
        load_bias_i = 1'b1;
        @(posedge clk);
        load_bias_i = 1'b0;
        #1 check_equal(acc_o, bias_mem[0], "load_bias");

        calc = bias_mem[0];
        for (i = 0; i < 9; i = i + 1) begin
            data_i = input_mem[input_idx[i]] * weight_mem[i];
            calc = calc + data_i;
            en_i = 1'b1;
            @(posedge clk);
            #1 check_equal(acc_o, calc, "accumulate");
        end
        en_i = 1'b0;
        check_equal(acc_o, expected_mem[0], "fixture output[0]");

        clear_i = 1'b1;
        @(posedge clk);
        clear_i = 1'b0;
        #1 check_equal(acc_o, 0, "clear");

        $display("PASS: tb_acc");
        $finish;
    end
endmodule
