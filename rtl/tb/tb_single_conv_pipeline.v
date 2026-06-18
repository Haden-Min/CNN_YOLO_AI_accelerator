`timescale 1ns/1ps

module tb_single_conv_pipeline;
    localparam DATA_WIDTH = 8;
    localparam MUL_WIDTH  = 16;
    localparam ACC_WIDTH  = 32;
    localparam IC = 1;
    localparam OC = 1;
    localparam IN_H = 5;
    localparam IN_W = 5;
    localparam K_H = 3;
    localparam K_W = 3;
    localparam OUT_H = 3;
    localparam OUT_W = 3;
    localparam INPUT_SIZE = IC * IN_H * IN_W;
    localparam WEIGHT_SIZE = OC * IC * K_H * K_W;
    localparam BIAS_SIZE = OC;
    localparam OUTPUT_SIZE = OC * OUT_H * OUT_W;
    localparam INPUT_ADDR_WIDTH = 5;
    localparam WEIGHT_ADDR_WIDTH = 4;
    localparam BIAS_ADDR_WIDTH = 1;
    localparam OUTPUT_ADDR_WIDTH = 4;

    reg clk;
    reg rst_n;
    reg start_i;

    reg input_load_en_i;
    reg [INPUT_ADDR_WIDTH-1:0] input_load_addr_i;
    reg signed [DATA_WIDTH-1:0] input_stream_data_i;

    reg weight_load_en_i;
    reg [WEIGHT_ADDR_WIDTH-1:0] weight_load_addr_i;
    reg signed [DATA_WIDTH-1:0] weight_stream_data_i;

    reg signed [ACC_WIDTH-1:0] bias_data_i;

    wire [BIAS_ADDR_WIDTH-1:0] bias_addr_o;
    wire [OUTPUT_ADDR_WIDTH-1:0] output_addr_o;
    wire output_we_o;
    wire busy_o;
    wire done_o;
    wire signed [ACC_WIDTH-1:0] output_data_o;

    reg signed [DATA_WIDTH-1:0] input_mem [0:INPUT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] weight_mem [0:WEIGHT_SIZE-1];
    reg signed [ACC_WIDTH-1:0] bias_mem [0:BIAS_SIZE-1];
    reg signed [ACC_WIDTH-1:0] expected_mem [0:OUTPUT_SIZE-1];

    integer fd;
    integer code;
    integer value;
    integer count;
    integer i;
    integer write_count;
    integer mismatch_count;
    integer done_seen;
    integer cycles;

    top_single_conv_pipeline #(
        .DATA_WIDTH(DATA_WIDTH),
        .MUL_WIDTH(MUL_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .IC(IC),
        .OC(OC),
        .IN_H(IN_H),
        .IN_W(IN_W),
        .K_H(K_H),
        .K_W(K_W),
        .OUT_H(OUT_H),
        .OUT_W(OUT_W),
        .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH),
        .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
        .BIAS_ADDR_WIDTH(BIAS_ADDR_WIDTH),
        .OUTPUT_ADDR_WIDTH(OUTPUT_ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_i(start_i),
        .input_load_en_i(input_load_en_i),
        .input_load_addr_i(input_load_addr_i),
        .input_stream_data_i(input_stream_data_i),
        .weight_load_en_i(weight_load_en_i),
        .weight_load_addr_i(weight_load_addr_i),
        .weight_stream_data_i(weight_stream_data_i),
        .bias_data_i(bias_data_i),
        .bias_addr_o(bias_addr_o),
        .output_addr_o(output_addr_o),
        .output_we_o(output_we_o),
        .busy_o(busy_o),
        .done_o(done_o),
        .output_data_o(output_data_o)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    always @(*) begin
        bias_data_i = bias_mem[bias_addr_o];
    end

    task load_input_file;
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

    task load_weight_file;
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

    task load_bias_file;
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

    task load_expected_file;
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

    task preload_input_buffer;
        begin
            input_load_en_i = 1'b1;
            for (i = 0; i < INPUT_SIZE; i = i + 1) begin
                input_load_addr_i = i[INPUT_ADDR_WIDTH-1:0];
                input_stream_data_i = input_mem[i];
                @(posedge clk);
            end
            input_load_en_i = 1'b0;
            input_load_addr_i = {INPUT_ADDR_WIDTH{1'b0}};
            input_stream_data_i = {DATA_WIDTH{1'b0}};
            @(posedge clk);
        end
    endtask

    task preload_weight_buffer;
        begin
            weight_load_en_i = 1'b1;
            for (i = 0; i < WEIGHT_SIZE; i = i + 1) begin
                weight_load_addr_i = i[WEIGHT_ADDR_WIDTH-1:0];
                weight_stream_data_i = weight_mem[i];
                @(posedge clk);
            end
            weight_load_en_i = 1'b0;
            weight_load_addr_i = {WEIGHT_ADDR_WIDTH{1'b0}};
            weight_stream_data_i = {DATA_WIDTH{1'b0}};
            @(posedge clk);
        end
    endtask

    initial begin
        load_input_file();
        load_weight_file();
        load_bias_file();
        load_expected_file();

        start_i = 1'b0;
        input_load_en_i = 1'b0;
        input_load_addr_i = {INPUT_ADDR_WIDTH{1'b0}};
        input_stream_data_i = {DATA_WIDTH{1'b0}};
        weight_load_en_i = 1'b0;
        weight_load_addr_i = {WEIGHT_ADDR_WIDTH{1'b0}};
        weight_stream_data_i = {DATA_WIDTH{1'b0}};
        write_count = 0;
        mismatch_count = 0;
        done_seen = 0;
        cycles = 0;

        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        preload_input_buffer();
        preload_weight_buffer();

        start_i = 1'b1;
        @(posedge clk);
        start_i = 1'b0;

        while (done_seen == 0 && cycles < 200) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;

            if (output_we_o) begin
                $display("OUT: output_addr=%0d got=%0d expected=%0d",
                         output_addr_o, output_data_o, expected_mem[output_addr_o]);

                if (output_data_o !== expected_mem[output_addr_o]) begin
                    $display("MISMATCH: output_addr=%0d got=%0d expected=%0d",
                             output_addr_o, output_data_o, expected_mem[output_addr_o]);
                    mismatch_count = mismatch_count + 1;
                end
                write_count = write_count + 1;
            end

            if (done_o) begin
                done_seen = 1;
            end
        end

        if (cycles >= 200) begin
            $display("FAIL: timeout waiting for done_o");
            $finish;
        end
        if (write_count != OUTPUT_SIZE) begin
            $display("FAIL: write_count=%0d expected=%0d", write_count, OUTPUT_SIZE);
            $finish;
        end

        if (mismatch_count != 0) begin
            $display("FAIL: mismatch_count=%0d writes=%0d cycles=%0d",
                     mismatch_count, write_count, cycles);
        end
        else begin
            $display("PASS: tb_single_conv_pipeline writes=%0d cycles=%0d",
                     write_count, cycles);
        end

        $finish;
    end
endmodule
