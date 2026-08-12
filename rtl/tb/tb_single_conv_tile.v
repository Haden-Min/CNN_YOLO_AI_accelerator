`timescale 1ns/1ps

module tb_single_conv_tile #(
    parameter TILE_WIDTH = 28,
    parameter TILE_HEIGHT = 28,
    parameter ENABLE_BACKPRESSURE = 1
);
    localparam DATA_WIDTH = 8;
    localparam ACC_WIDTH = 32;
    localparam OUTPUT_WIDTH = TILE_WIDTH - 2;
    localparam OUTPUT_HEIGHT = TILE_HEIGHT - 2;
    localparam INPUT_SIZE = TILE_WIDTH * TILE_HEIGHT;
    localparam OUTPUT_SIZE = OUTPUT_WIDTH * OUTPUT_HEIGHT;
    localparam OUTPUT_ADDR_WIDTH = $clog2(OUTPUT_SIZE);

    reg clk;
    reg rst_n;
    reg start_i;

    reg signed [DATA_WIDTH-1:0] s_data_i;
    reg s_valid_i;
    wire s_ready_o;
    reg s_last_i;

    reg weight_load_en_i;
    reg [3:0] weight_load_addr_i;
    reg signed [DATA_WIDTH-1:0] weight_load_data_i;
    reg bias_load_en_i;
    reg signed [ACC_WIDTH-1:0] bias_load_data_i;

    wire signed [ACC_WIDTH-1:0] result_data_o;
    wire [OUTPUT_ADDR_WIDTH-1:0] result_addr_o;
    wire result_last_o;
    wire result_valid_o;
    reg result_ready_i;
    wire busy_o;
    wire done_o;
    wire [1:0] input_error_o;
    wire [3:0] state_o;

    reg signed [DATA_WIDTH-1:0] input_mem [0:INPUT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] weight_mem [0:8];
    reg signed [ACC_WIDTH-1:0] expected_mem [0:OUTPUT_SIZE-1];

    integer x;
    integer y;
    integer kx;
    integer ky;
    integer idx;
    integer out_idx;
    integer sum;
    integer send_count;
    integer recv_count;
    integer mismatch_count;
    integer wait_cycles;
    integer ready_cycle;
    integer done_seen;

    top_single_conv_tile #(
        .TILE_WIDTH(TILE_WIDTH),
        .TILE_HEIGHT(TILE_HEIGHT),
        .OUTPUT_WIDTH(OUTPUT_WIDTH),
        .OUTPUT_HEIGHT(OUTPUT_HEIGHT),
        .OUTPUT_SIZE(OUTPUT_SIZE),
        .OUTPUT_ADDR_WIDTH(OUTPUT_ADDR_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_i(start_i),
        .s_data_i(s_data_i),
        .s_valid_i(s_valid_i),
        .s_ready_o(s_ready_o),
        .s_last_i(s_last_i),
        .weight_load_en_i(weight_load_en_i),
        .weight_load_addr_i(weight_load_addr_i),
        .weight_load_data_i(weight_load_data_i),
        .bias_load_en_i(bias_load_en_i),
        .bias_load_data_i(bias_load_data_i),
        .result_data_o(result_data_o),
        .result_addr_o(result_addr_o),
        .result_last_o(result_last_o),
        .result_valid_o(result_valid_o),
        .result_ready_i(result_ready_i),
        .busy_o(busy_o),
        .done_o(done_o),
        .input_error_o(input_error_o),
        .state_o(state_o)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task load_parameters;
        integer wi;
        begin
            for (wi = 0; wi < 9; wi = wi + 1) begin
                @(negedge clk);
                weight_load_en_i = 1'b1;
                weight_load_addr_i = wi[3:0];
                weight_load_data_i = weight_mem[wi];
            end
            @(negedge clk);
            weight_load_en_i = 1'b0;
            weight_load_addr_i = 4'd0;
            weight_load_data_i = 0;

            bias_load_en_i = 1'b1;
            bias_load_data_i = 32'sd17;
            @(negedge clk);
            bias_load_en_i = 1'b0;
            bias_load_data_i = 0;
            repeat (2) @(posedge clk);
        end
    endtask

    task send_tile;
        begin
            send_count = 0;
            s_valid_i = 1'b0;
            s_last_i = 1'b0;

            while (send_count < INPUT_SIZE) begin
                @(negedge clk);
                s_valid_i = 1'b1;
                s_data_i = input_mem[send_count];
                s_last_i = (send_count == INPUT_SIZE - 1);
                @(posedge clk);
                if (s_ready_o) begin
                    send_count = send_count + 1;
                end
            end

            @(negedge clk);
            s_valid_i = 1'b0;
            s_last_i = 1'b0;
            s_data_i = 0;
        end
    endtask

    task receive_results;
        begin
            recv_count = 0;
            mismatch_count = 0;
            ready_cycle = 0;
            result_ready_i = 1'b0;

            while (recv_count < OUTPUT_SIZE) begin
                @(negedge clk);
                if (ENABLE_BACKPRESSURE) begin
                    result_ready_i = ((ready_cycle % 17) >= 6);
                end
                else begin
                    result_ready_i = 1'b1;
                end
                ready_cycle = ready_cycle + 1;
                @(posedge clk);

                if (result_valid_o && result_ready_i) begin
                    if (result_addr_o !== recv_count[OUTPUT_ADDR_WIDTH-1:0]) begin
                        $display("FAIL: address mismatch index=%0d got=%0d", recv_count, result_addr_o);
                        mismatch_count = mismatch_count + 1;
                    end

                    if (result_data_o !== expected_mem[recv_count]) begin
                        if (mismatch_count < 20) begin
                            $display("FAIL: data mismatch index=%0d got=%0d expected=%0d",
                                     recv_count, result_data_o, expected_mem[recv_count]);
                        end
                        mismatch_count = mismatch_count + 1;
                    end

                    if (result_last_o !== (recv_count == OUTPUT_SIZE - 1)) begin
                        $display("FAIL: last mismatch index=%0d last=%0b", recv_count, result_last_o);
                        mismatch_count = mismatch_count + 1;
                    end

                    recv_count = recv_count + 1;
                end
            end

            @(negedge clk);
            result_ready_i = 1'b0;
        end
    endtask

    initial begin
        weight_mem[0] = -2;
        weight_mem[1] = 1;
        weight_mem[2] = 3;
        weight_mem[3] = 0;
        weight_mem[4] = -1;
        weight_mem[5] = 2;
        weight_mem[6] = 1;
        weight_mem[7] = -3;
        weight_mem[8] = 2;

        for (y = 0; y < TILE_HEIGHT; y = y + 1) begin
            for (x = 0; x < TILE_WIDTH; x = x + 1) begin
                idx = y * TILE_WIDTH + x;
                input_mem[idx] = ((y * 17 + x * 5 + 3) % 31) - 15;
            end
        end

        for (y = 0; y < OUTPUT_HEIGHT; y = y + 1) begin
            for (x = 0; x < OUTPUT_WIDTH; x = x + 1) begin
                sum = 17;
                for (ky = 0; ky < 3; ky = ky + 1) begin
                    for (kx = 0; kx < 3; kx = kx + 1) begin
                        sum = sum + input_mem[(y + ky) * TILE_WIDTH + (x + kx)] *
                                    weight_mem[ky * 3 + kx];
                    end
                end
                expected_mem[y * OUTPUT_WIDTH + x] = sum;
            end
        end

        rst_n = 1'b0;
        start_i = 1'b0;
        s_data_i = 0;
        s_valid_i = 1'b0;
        s_last_i = 1'b0;
        weight_load_en_i = 1'b0;
        weight_load_addr_i = 0;
        weight_load_data_i = 0;
        bias_load_en_i = 1'b0;
        bias_load_data_i = 0;
        result_ready_i = 1'b0;
        done_seen = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        load_parameters();

        @(negedge clk);
        start_i = 1'b1;
        @(negedge clk);
        start_i = 1'b0;

        fork
            send_tile();
            receive_results();
            begin
                wait_cycles = 0;
                while (!done_seen && wait_cycles < 200000) begin
                    @(posedge clk);
                    wait_cycles = wait_cycles + 1;
                    if (done_o) done_seen = 1;
                end
            end
        join

        if (!done_seen) begin
            $display("FAIL: timeout state=%0d send=%0d recv=%0d", state_o, send_count, recv_count);
            $finish;
        end
        if (send_count != INPUT_SIZE) begin
            $display("FAIL: input count=%0d expected=%0d", send_count, INPUT_SIZE);
            $finish;
        end
        if (recv_count != OUTPUT_SIZE) begin
            $display("FAIL: output count=%0d expected=%0d", recv_count, OUTPUT_SIZE);
            $finish;
        end
        if (input_error_o != 0) begin
            $display("FAIL: input protocol error=0x%0x", input_error_o);
            $finish;
        end
        if (mismatch_count != 0) begin
            $display("FAIL: mismatches=%0d", mismatch_count);
            $finish;
        end

        $display("PASS: tb_single_conv_tile tile=%0dx%0d inputs=%0d outputs=%0d cycles=%0d backpressure=%0d",
                 TILE_WIDTH, TILE_HEIGHT, send_count, recv_count, wait_cycles,
                 ENABLE_BACKPRESSURE);
        $finish;
    end

endmodule
