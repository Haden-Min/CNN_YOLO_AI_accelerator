`timescale 1ns/1ps

module tb_single_conv_pipeline_axi_v2_416;
    localparam DATA_WIDTH = 8;
    localparam MUL_WIDTH  = 16;
    localparam ACC_WIDTH  = 32;
    localparam IC = 1;
    localparam OC = 1;
    localparam IN_H = 416;
    localparam IN_W = 416;
    localparam K_H = 3;
    localparam K_W = 3;
    localparam OUT_H = 414;
    localparam OUT_W = 414;
    localparam INPUT_SIZE = IC * IN_H * IN_W;
    localparam WEIGHT_SIZE = OC * IC * K_H * K_W;
    localparam BIAS_SIZE = OC;
    localparam OUTPUT_SIZE = OC * OUT_H * OUT_W;
    localparam INPUT_ROW_WORDS = IC * IN_W;
    localparam AXI_DATA_WIDTH = 32;
    localparam AXI_ADDR_WIDTH = 6;
    localparam TIMEOUT_CYCLES = 4000000;
    localparam PROGRESS_STEP = 10000;

    reg clk;
    reg rst_n;

    reg [AXI_ADDR_WIDTH-1:0] s_axi_awaddr;
    reg [2:0] s_axi_awprot;
    reg s_axi_awvalid;
    wire s_axi_awready;
    reg [AXI_DATA_WIDTH-1:0] s_axi_wdata;
    reg [(AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb;
    reg s_axi_wvalid;
    wire s_axi_wready;
    wire [1:0] s_axi_bresp;
    wire s_axi_bvalid;
    reg s_axi_bready;
    reg [AXI_ADDR_WIDTH-1:0] s_axi_araddr;
    reg [2:0] s_axi_arprot;
    reg s_axi_arvalid;
    wire s_axi_arready;
    wire [AXI_DATA_WIDTH-1:0] s_axi_rdata;
    wire [1:0] s_axi_rresp;
    wire s_axi_rvalid;
    reg s_axi_rready;

    reg [AXI_DATA_WIDTH-1:0] s_axis_tdata;
    reg s_axis_tvalid;
    wire s_axis_tready;
    reg s_axis_tlast;

    wire [AXI_DATA_WIDTH-1:0] m_axis_tdata;
    wire m_axis_tvalid;
    reg m_axis_tready;
    wire m_axis_tlast;
    wire irq;

    reg signed [DATA_WIDTH-1:0] input_mem [0:INPUT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] weight_mem [0:WEIGHT_SIZE-1];
    reg signed [ACC_WIDTH-1:0] bias_mem [0:BIAS_SIZE-1];
    reg signed [ACC_WIDTH-1:0] expected_mem [0:OUTPUT_SIZE-1];

    integer fd;
    integer code;
    integer value;
    integer count;
    integer row_idx;
    integer ch_idx;
    integer col_idx;
    integer flat_idx;
    integer i;
    integer recv_count;
    integer mismatch_count;
    integer timeout_done;
    integer recv_done;
    integer send_done;
    integer last_seen_count;
    integer status_value;
    integer stream_in_value;
    integer stream_out_value;
    integer error_value;
    integer ready_wait;
    integer recv_wait_cycles;
    integer aw_done;
    integer w_done;
    integer write_wait;
    reg signed [ACC_WIDTH-1:0] got_value;

    top_single_conv_pipeline_axi #(
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
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) dut (
        .aclk(clk),
        .aresetn(rst_n),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awprot(s_axi_awprot),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arprot(s_axi_arprot),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .irq(irq)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task open_input_fixture;
        output integer file_desc;
        begin
            file_desc = $fopen("C:/Users/hanyu/Documents/CNN Accelerator/CNN_YOLO_AI_accelerator/sw/fixture/single_conv_416/input_int8.hex", "r");
            if (file_desc == 0) file_desc = $fopen("sw/fixture/single_conv_416/input_int8.hex", "r");
            if (file_desc == 0) file_desc = $fopen("../sw/fixture/single_conv_416/input_int8.hex", "r");
            if (file_desc == 0) file_desc = $fopen("../../sw/fixture/single_conv_416/input_int8.hex", "r");
        end
    endtask

    task open_weight_fixture;
        output integer file_desc;
        begin
            file_desc = $fopen("C:/Users/hanyu/Documents/CNN Accelerator/CNN_YOLO_AI_accelerator/sw/fixture/single_conv_416/weight_int8.hex", "r");
            if (file_desc == 0) file_desc = $fopen("sw/fixture/single_conv_416/weight_int8.hex", "r");
            if (file_desc == 0) file_desc = $fopen("../sw/fixture/single_conv_416/weight_int8.hex", "r");
            if (file_desc == 0) file_desc = $fopen("../../sw/fixture/single_conv_416/weight_int8.hex", "r");
        end
    endtask

    task open_bias_fixture;
        output integer file_desc;
        begin
            file_desc = $fopen("C:/Users/hanyu/Documents/CNN Accelerator/CNN_YOLO_AI_accelerator/sw/fixture/single_conv_416/bias_int32.hex", "r");
            if (file_desc == 0) file_desc = $fopen("sw/fixture/single_conv_416/bias_int32.hex", "r");
            if (file_desc == 0) file_desc = $fopen("../sw/fixture/single_conv_416/bias_int32.hex", "r");
            if (file_desc == 0) file_desc = $fopen("../../sw/fixture/single_conv_416/bias_int32.hex", "r");
        end
    endtask

    task open_expected_fixture;
        output integer file_desc;
        begin
            file_desc = $fopen("C:/Users/hanyu/Documents/CNN Accelerator/CNN_YOLO_AI_accelerator/sw/fixture/single_conv_416/expected_acc_int32.hex", "r");
            if (file_desc == 0) file_desc = $fopen("sw/fixture/single_conv_416/expected_acc_int32.hex", "r");
            if (file_desc == 0) file_desc = $fopen("../sw/fixture/single_conv_416/expected_acc_int32.hex", "r");
            if (file_desc == 0) file_desc = $fopen("../../sw/fixture/single_conv_416/expected_acc_int32.hex", "r");
        end
    endtask

    task load_input_file;
        begin
            count = 0;
            open_input_fixture(fd);
            if (fd == 0) begin
                $display("FAIL: cannot open input fixture input_int8.hex");
                $finish;
            end
            while (!$feof(fd)) begin
                code = $fscanf(fd, "%d\n", value);
                if (code == 1) begin input_mem[count] = value; count = count + 1; end
            end
            $fclose(fd);
            if (count != INPUT_SIZE) begin
                $display("FAIL: input fixture count=%0d expected=%0d", count, INPUT_SIZE);
                $finish;
            end
        end
    endtask

    task load_weight_file;
        begin
            count = 0;
            open_weight_fixture(fd);
            if (fd == 0) begin
                $display("FAIL: cannot open weight fixture weight_int8.hex");
                $finish;
            end
            while (!$feof(fd)) begin
                code = $fscanf(fd, "%d\n", value);
                if (code == 1) begin weight_mem[count] = value; count = count + 1; end
            end
            $fclose(fd);
            if (count != WEIGHT_SIZE) begin
                $display("FAIL: weight fixture count=%0d expected=%0d", count, WEIGHT_SIZE);
                $finish;
            end
        end
    endtask

    task load_bias_file;
        begin
            count = 0;
            open_bias_fixture(fd);
            if (fd == 0) begin
                $display("FAIL: cannot open bias fixture bias_int32.hex");
                $finish;
            end
            while (!$feof(fd)) begin
                code = $fscanf(fd, "%d\n", value);
                if (code == 1) begin bias_mem[count] = value; count = count + 1; end
            end
            $fclose(fd);
            if (count != BIAS_SIZE) begin
                $display("FAIL: bias fixture count=%0d expected=%0d", count, BIAS_SIZE);
                $finish;
            end
        end
    endtask

    task load_expected_file;
        begin
            count = 0;
            open_expected_fixture(fd);
            if (fd == 0) begin
                $display("FAIL: cannot open expected fixture expected_acc_int32.hex");
                $finish;
            end
            while (!$feof(fd)) begin
                code = $fscanf(fd, "%d\n", value);
                if (code == 1) begin expected_mem[count] = value; count = count + 1; end
            end
            $fclose(fd);
            if (count != OUTPUT_SIZE) begin
                $display("FAIL: expected fixture count=%0d expected=%0d", count, OUTPUT_SIZE);
                $finish;
            end
        end
    endtask

    task axi_write;
        input [AXI_ADDR_WIDTH-1:0] addr;
        input [AXI_DATA_WIDTH-1:0] data;
        begin
            @(negedge clk);
            s_axi_awaddr = addr;
            s_axi_wdata = data;
            s_axi_wstrb = 4'hf;
            s_axi_awvalid = 1'b1;
            s_axi_wvalid = 1'b1;
            s_axi_bready = 1'b0;
            aw_done = 0;
            w_done = 0;
            write_wait = 0;
            while (!aw_done || !w_done) begin
                @(negedge clk);
                if (s_axi_awready) aw_done = 1;
                if (s_axi_wready) w_done = 1;
                write_wait = write_wait + 1;
                if (write_wait > 1000) begin
                    $display("FAIL: timeout waiting for AXI-Lite write ready addr=0x%02x aw_done=%0d w_done=%0d",
                             addr, aw_done, w_done);
                    $finish;
                end
            end
            @(negedge clk);
            s_axi_awvalid = 1'b0;
            s_axi_wvalid = 1'b0;
            write_wait = 0;
            while (!s_axi_bvalid) begin
                @(negedge clk);
                write_wait = write_wait + 1;
                if (write_wait > 1000) begin
                    $display("FAIL: timeout waiting for AXI-Lite bvalid addr=0x%02x", addr);
                    $finish;
                end
            end
            s_axi_bready = 1'b1;
            @(negedge clk);
            s_axi_bready = 1'b0;
            s_axi_awaddr = {AXI_ADDR_WIDTH{1'b0}};
            s_axi_wdata = {AXI_DATA_WIDTH{1'b0}};
            s_axi_wstrb = {(AXI_DATA_WIDTH/8){1'b0}};
        end
    endtask

    task axi_read;
        input [AXI_ADDR_WIDTH-1:0] addr;
        output integer data;
        begin
            @(negedge clk);
            s_axi_araddr = addr;
            s_axi_arvalid = 1'b1;
            s_axi_rready = 1'b0;
            while (!s_axi_arready) begin
                @(negedge clk);
            end
            @(negedge clk);
            s_axi_arvalid = 1'b0;
            while (!s_axi_rvalid) begin
                @(negedge clk);
            end
            data = s_axi_rdata;
            s_axi_rready = 1'b1;
            @(negedge clk);
            s_axi_rready = 1'b0;
            s_axi_araddr = {AXI_ADDR_WIDTH{1'b0}};
        end
    endtask

    task axis_send_word;
        input signed [AXI_DATA_WIDTH-1:0] data;
        input last;
        begin
            @(negedge clk);
            s_axis_tdata = data;
            s_axis_tlast = last;
            s_axis_tvalid = 1'b1;
            ready_wait = 0;
            while (!s_axis_tready) begin
                @(negedge clk);
                ready_wait = ready_wait + 1;
                if (ready_wait > TIMEOUT_CYCLES) begin
                    $display("FAIL: timeout waiting for s_axis_tready");
                    $finish;
                end
            end
            @(negedge clk);
            s_axis_tvalid = 1'b0;
            s_axis_tlast = 1'b0;
            s_axis_tdata = {AXI_DATA_WIDTH{1'b0}};
        end
    endtask

    task axis_send_input_row;
        input integer send_row_idx;
        input integer last_row_flag;
        begin
            if ((send_row_idx < K_H) || ((send_row_idx % 32) == 0) || (send_row_idx == IN_H - 1)) begin
                $display("[DMA-MM2S] send input row=%0d", send_row_idx);
            end
            for (ch_idx = 0; ch_idx < IC; ch_idx = ch_idx + 1) begin
                for (col_idx = 0; col_idx < IN_W; col_idx = col_idx + 1) begin
                    flat_idx = ch_idx * IN_H * IN_W + send_row_idx * IN_W + col_idx;
                    axis_send_word(input_mem[flat_idx],
                                   last_row_flag && (ch_idx == IC - 1) && (col_idx == IN_W - 1));
                end
            end
        end
    endtask

    task axis_send_payload;
        begin
            $display("[DMA-MM2S] stream initial input rows");
            for (row_idx = 0; row_idx < K_H; row_idx = row_idx + 1) begin
                axis_send_input_row(row_idx, 0);
            end

            $display("[DMA-MM2S] stream weights");
            for (i = 0; i < WEIGHT_SIZE; i = i + 1) begin
                axis_send_word(weight_mem[i], 1'b0);
            end

            $display("[DMA-MM2S] stream bias");
            for (i = 0; i < BIAS_SIZE; i = i + 1) begin
                axis_send_word(bias_mem[i], 1'b0);
            end

            $display("[DMA-MM2S] stream remaining input rows with wrapper backpressure");
            for (row_idx = K_H; row_idx < IN_H; row_idx = row_idx + 1) begin
                axis_send_input_row(row_idx, row_idx == IN_H - 1);
            end
            send_done = 1;
            $display("[DMA-MM2S] stream payload done");
        end
    endtask

    task axis_recv_outputs;
        begin
            recv_count = 0;
            mismatch_count = 0;
            last_seen_count = 0;
            recv_wait_cycles = 0;
            m_axis_tready = 1'b1;
            while (recv_count < OUTPUT_SIZE) begin
                @(posedge clk);
                recv_wait_cycles = recv_wait_cycles + 1;
                if (recv_wait_cycles > TIMEOUT_CYCLES) begin
                    $display("FAIL: timeout waiting for AXI output, recv_count=%0d", recv_count);
                    $finish;
                end
                if (m_axis_tvalid && m_axis_tready) begin
                    got_value = m_axis_tdata;
                    if (got_value !== expected_mem[recv_count]) begin
                        if (mismatch_count < 20) begin
                            $display("[FAIL] AXI output mismatch addr=%0d got=%0d expected=%0d",
                                     recv_count, got_value, expected_mem[recv_count]);
                        end
                        mismatch_count = mismatch_count + 1;
                    end
                    if ((recv_count < 5) ||
                        (recv_count >= (OUTPUT_SIZE / 2) && recv_count < (OUTPUT_SIZE / 2 + 5)) ||
                        (recv_count >= (OUTPUT_SIZE - 5))) begin
                        $display("[SAMPLE] AXI output addr=%0d got=%0d expected=%0d",
                                 recv_count, got_value, expected_mem[recv_count]);
                    end
                    if (((recv_count + 1) % PROGRESS_STEP) == 0) begin
                        $display("[PROGRESS] AXI recv=%0d/%0d", recv_count + 1, OUTPUT_SIZE);
                    end
                    if (m_axis_tlast) begin
                        last_seen_count = last_seen_count + 1;
                        if (recv_count != OUTPUT_SIZE - 1) begin
                            $display("[FAIL] AXI tlast asserted early at addr=%0d", recv_count);
                            mismatch_count = mismatch_count + 1;
                        end
                    end
                    recv_count = recv_count + 1;
                end
            end
            if (last_seen_count != 1) begin
                $display("[FAIL] AXI tlast count=%0d expected=1", last_seen_count);
                mismatch_count = mismatch_count + 1;
            end
            recv_done = 1;
            @(negedge clk);
            m_axis_tready = 1'b0;
        end
    endtask

    initial begin
        load_input_file();
        load_weight_file();
        load_bias_file();
        load_expected_file();

        rst_n = 1'b0;
        s_axi_awaddr = {AXI_ADDR_WIDTH{1'b0}};
        s_axi_awprot = 3'b000;
        s_axi_awvalid = 1'b0;
        s_axi_wdata = {AXI_DATA_WIDTH{1'b0}};
        s_axi_wstrb = {(AXI_DATA_WIDTH/8){1'b0}};
        s_axi_wvalid = 1'b0;
        s_axi_bready = 1'b0;
        s_axi_araddr = {AXI_ADDR_WIDTH{1'b0}};
        s_axi_arprot = 3'b000;
        s_axi_arvalid = 1'b0;
        s_axi_rready = 1'b0;
        s_axis_tdata = {AXI_DATA_WIDTH{1'b0}};
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
        m_axis_tready = 1'b0;
        timeout_done = 0;
        recv_done = 0;
        send_done = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        $display("[AXI-LITE] start wrapper");
        axi_write(6'h00, 32'h00000001);

        axis_send_payload();
        axis_recv_outputs();

        axi_read(6'h04, status_value);
        axi_read(6'h08, stream_in_value);
        axi_read(6'h0c, stream_out_value);
        axi_read(6'h18, error_value);

        if (!send_done) begin
            $display("FAIL: input DMA stream did not finish");
            $finish;
        end
        if (stream_in_value != INPUT_SIZE + WEIGHT_SIZE + BIAS_SIZE) begin
            $display("FAIL: wrapper stream_in_count=%0d expected=%0d",
                     stream_in_value, INPUT_SIZE + WEIGHT_SIZE + BIAS_SIZE);
            $finish;
        end
        if (stream_out_value != OUTPUT_SIZE) begin
            $display("FAIL: wrapper stream_out_count=%0d expected=%0d",
                     stream_out_value, OUTPUT_SIZE);
            $finish;
        end
        if (error_value != 0) begin
            $display("FAIL: wrapper error_flags=0x%08x", error_value);
            $finish;
        end
        if (mismatch_count != 0) begin
            $display("FAIL: AXI wrapper mismatch_count=%0d", mismatch_count);
            $finish;
        end

        $display("PASS: tb_single_conv_pipeline_axi_v2_416 outputs=%0d stream_in=%0d status=0x%08x",
                 recv_count, stream_in_value, status_value);
        $finish;
    end
endmodule
