`timescale 1ns/1ps

module tb_mlt;
    localparam DATA_WIDTH = 8;
    localparam INPUT_SIZE = 25;
    localparam WEIGHT_SIZE = 9;

    reg signed [DATA_WIDTH-1:0] data_i;
    reg signed [DATA_WIDTH-1:0] kernel_i;
    wire signed [2*DATA_WIDTH-1:0] mul_o;

    reg signed [7:0] input_mem [0:INPUT_SIZE-1];
    reg signed [7:0] weight_mem [0:WEIGHT_SIZE-1];

    integer fd;
    integer code;
    integer value;
    integer count;
    integer i;
    integer j;
    integer exp;

    mlt #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .data_i(data_i),
        .kernel_i(kernel_i),
        .mul_o(mul_o)
    );

    task load_input;
        begin
            count = 0;
            fd = $fopen("D:/a.Projects/cnn_accelerator/CNN_YOLO_AI_accelerator/sw/fixture/single_conv_001/input_int8.hex", "r");
            if (fd == 0) begin
                $display("FAIL: cannot open input file");
                $finish;
            end
            while (!$feof(fd)) begin
                code = $fscanf(fd, "%d\n", value);
                if (code == 1) begin
                    input_mem[count] = value;
                    count = count + 1;
                end
            end
            $fclose(fd);
            if (count != INPUT_SIZE) begin
                $display("FAIL: input count=%0d", count);
                $finish;
            end
        end
    endtask

    task load_weight;
        begin
            count = 0;
            fd = $fopen("D:/a.Projects/cnn_accelerator/CNN_YOLO_AI_accelerator/sw/fixture/single_conv_001/weight_int8.hex", "r");
            if (fd == 0) begin
                $display("FAIL: cannot open weight file");
                $finish;
            end
            while (!$feof(fd)) begin
                code = $fscanf(fd, "%d\n", value);
                if (code == 1) begin
                    weight_mem[count] = value;
                    count = count + 1;
                end
            end
            $fclose(fd);
            if (count != WEIGHT_SIZE) begin
                $display("FAIL: weight count=%0d", count);
                $finish;
            end
        end
    endtask

    initial begin
        load_input();
        load_weight();

        for (i = 0; i < INPUT_SIZE; i = i + 1) begin
            for (j = 0; j < WEIGHT_SIZE; j = j + 1) begin
                data_i = input_mem[i];
                kernel_i = weight_mem[j];
                exp = input_mem[i] * weight_mem[j];
                #1;
                if (mul_o !== exp[15:0]) begin
                    $display("FAIL: i=%0d j=%0d data=%0d kernel=%0d got=%0d expected=%0d",
                             i, j, data_i, kernel_i, mul_o, exp);
                    $finish;
                end
            end
        end

        $display("PASS: tb_mlt");
        $finish;
    end
endmodule
