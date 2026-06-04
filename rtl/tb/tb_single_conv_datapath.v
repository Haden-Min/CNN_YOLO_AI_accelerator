`timescale 1ns/1ps

module tb_single_conv_datapath;
    localparam DATA_WIDTH = 8;
    localparam MUL_WIDTH  = 16;
    localparam ACC_WIDTH  = 32;
    localparam INPUT_W = 5;
    localparam OUTPUT_W = 3;
    localparam OUTPUT_H = 3;
    localparam KERNEL = 3;

    reg clk;
    reg rst_n;
    reg acc_clear_i;
    reg acc_load_bias_i;
    reg mac_en_i;
    reg signed [DATA_WIDTH-1:0] input_data_i;
    reg signed [DATA_WIDTH-1:0] weight_data_i;
    reg signed [ACC_WIDTH-1:0] bias_data_i;
    wire signed [ACC_WIDTH-1:0] acc_o;

    reg signed [7:0] input_mem [0:24];
    reg signed [7:0] weight_mem [0:8];
    reg signed [ACC_WIDTH-1:0] bias_mem [0:0];
    reg signed [ACC_WIDTH-1:0] expected_mem [0:8];

    integer fd;
    integer code;
    integer value;
    integer count;
    integer oh;
    integer ow;
    integer kh;
    integer kw;
    integer out_idx;
    integer in_idx;
    integer w_idx;

    single_conv_datapath #(
        .DATA_WIDTH(DATA_WIDTH),
        .MUL_WIDTH(MUL_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .acc_clear_i(acc_clear_i),
        .acc_load_bias_i(acc_load_bias_i),
        .mac_en_i(mac_en_i),
        .input_data_i(input_data_i),
        .weight_data_i(weight_data_i),
        .bias_data_i(bias_data_i),
        .acc_o(acc_o)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

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

        acc_clear_i = 1'b0;
        acc_load_bias_i = 1'b0;
        mac_en_i = 1'b0;
        input_data_i = 0;
        weight_data_i = 0;
        bias_data_i = bias_mem[0];

        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        out_idx = 0;
        for (oh = 0; oh < OUTPUT_H; oh = oh + 1) begin
            for (ow = 0; ow < OUTPUT_W; ow = ow + 1) begin
                acc_load_bias_i = 1'b1;
                @(posedge clk);
                #1;
                acc_load_bias_i = 1'b0;

                for (kh = 0; kh < KERNEL; kh = kh + 1) begin
                    for (kw = 0; kw < KERNEL; kw = kw + 1) begin
                        in_idx = (oh + kh) * INPUT_W + (ow + kw);
                        w_idx = kh * KERNEL + kw;
                        input_data_i = input_mem[in_idx];
                        weight_data_i = weight_mem[w_idx];
                        mac_en_i = 1'b1;
                        @(posedge clk);
                        #1;
                    end
                end
                mac_en_i = 1'b0;

                if (acc_o !== expected_mem[out_idx]) begin
                    $display("FAIL: output[%0d] got=%0d expected=%0d", out_idx, acc_o, expected_mem[out_idx]);
                    $finish;
                end
                out_idx = out_idx + 1;
            end
        end

        $display("PASS: tb_single_conv_datapath");
        $finish;
    end
endmodule
