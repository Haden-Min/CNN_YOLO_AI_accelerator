`timescale 1ns/1ps

module tb_single_conv_tile_axi #(
    parameter TILE_WIDTH = 28,
    parameter TILE_HEIGHT = 28,
    parameter ENABLE_BACKPRESSURE = 1,
    parameter CONTINUOUS_INPUT = 0
);
    localparam DATA_WIDTH = 8;
    localparam ACC_WIDTH = 32;
    localparam OUTPUT_WIDTH = TILE_WIDTH - 2;
    localparam OUTPUT_HEIGHT = TILE_HEIGHT - 2;
    localparam INPUT_SIZE = TILE_WIDTH * TILE_HEIGHT;
    localparam OUTPUT_SIZE = OUTPUT_WIDTH * OUTPUT_HEIGHT;

    reg clk;
    reg rst_n;

    reg [5:0] s_axi_awaddr;
    reg [2:0] s_axi_awprot;
    reg s_axi_awvalid;
    wire s_axi_awready;
    reg [31:0] s_axi_wdata;
    reg [3:0] s_axi_wstrb;
    reg s_axi_wvalid;
    wire s_axi_wready;
    wire [1:0] s_axi_bresp;
    wire s_axi_bvalid;
    reg s_axi_bready;
    reg [5:0] s_axi_araddr;
    reg [2:0] s_axi_arprot;
    reg s_axi_arvalid;
    wire s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0] s_axi_rresp;
    wire s_axi_rvalid;
    reg s_axi_rready;

    reg [31:0] s_axis_tdata;
    reg s_axis_tvalid;
    wire s_axis_tready;
    reg s_axis_tlast;

    wire [31:0] m_axis_tdata;
    wire m_axis_tvalid;
    reg m_axis_tready;
    wire m_axis_tlast;
    wire irq;

    reg signed [DATA_WIDTH-1:0] input_mem [0:INPUT_SIZE-1];
    reg signed [DATA_WIDTH-1:0] weight_mem [0:8];
    reg signed [ACC_WIDTH-1:0] expected_mem [0:OUTPUT_SIZE-1];

    integer x;
    integer y;
    integer kx;
    integer ky;
    integer idx;
    integer sum;
    integer send_count;
    integer recv_count;
    integer mismatch_count;
    integer recv_cycle;
    integer send_done;
    integer first_output_before_send_done;
    integer status_value;
    integer input_count_value;
    integer output_count_value;
    integer error_value;
    integer timeout_count;

    top_single_conv_tile_axi #(
        .TILE_WIDTH(TILE_WIDTH),
        .TILE_HEIGHT(TILE_HEIGHT),
        .OUTPUT_WIDTH(OUTPUT_WIDTH),
        .OUTPUT_HEIGHT(OUTPUT_HEIGHT),
        .INPUT_SIZE(INPUT_SIZE),
        .OUTPUT_SIZE(OUTPUT_SIZE),
        .OUTPUT_ADDR_WIDTH($clog2(OUTPUT_SIZE))
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

    task drive_aw;
        input [5:0] addr;
        begin
            @(negedge clk);
            s_axi_awaddr = addr;
            s_axi_awvalid = 1'b1;
            @(posedge clk);
            while (!s_axi_awready) @(posedge clk);
            @(negedge clk);
            s_axi_awvalid = 1'b0;
        end
    endtask

    task drive_w;
        input [31:0] data;
        begin
            @(negedge clk);
            s_axi_wdata = data;
            s_axi_wstrb = 4'hf;
            s_axi_wvalid = 1'b1;
            @(posedge clk);
            while (!s_axi_wready) @(posedge clk);
            @(negedge clk);
            s_axi_wvalid = 1'b0;
        end
    endtask

    task wait_b;
        begin
            s_axi_bready = 1'b1;
            @(posedge clk);
            while (!s_axi_bvalid) @(posedge clk);
            if (s_axi_bresp != 2'b00) begin
                $display("FAIL: AXI write response=%0b", s_axi_bresp);
                $finish;
            end
            @(negedge clk);
            s_axi_bready = 1'b0;
        end
    endtask

    task axi_write_aw_first;
        input [5:0] addr;
        input [31:0] data;
        begin
            drive_aw(addr);
            repeat (2) @(posedge clk);
            drive_w(data);
            wait_b();
        end
    endtask

    task axi_write_w_first;
        input [5:0] addr;
        input [31:0] data;
        begin
            drive_w(data);
            repeat (3) @(posedge clk);
            drive_aw(addr);
            wait_b();
        end
    endtask

    task axi_write_together;
        input [5:0] addr;
        input [31:0] data;
        begin
            fork
                drive_aw(addr);
                drive_w(data);
            join
            wait_b();
        end
    endtask

    task axi_read;
        input [5:0] addr;
        output integer value;
        begin
            @(negedge clk);
            s_axi_araddr = addr;
            s_axi_arvalid = 1'b1;
            s_axi_rready = 1'b1;
            @(posedge clk);
            while (!s_axi_arready) @(posedge clk);
            @(negedge clk);
            s_axi_arvalid = 1'b0;
            @(posedge clk);
            while (!s_axi_rvalid) @(posedge clk);
            value = s_axi_rdata;
            if (s_axi_rresp != 2'b00) begin
                $display("FAIL: AXI read response=%0b", s_axi_rresp);
                $finish;
            end
            @(negedge clk);
            s_axi_rready = 1'b0;
        end
    endtask

    task axis_send_word;
        input [31:0] data;
        input last;
        begin
            @(negedge clk);
            s_axis_tdata = data;
            s_axis_tlast = last;
            s_axis_tvalid = 1'b1;
            @(posedge clk);
            while (!s_axis_tready) @(posedge clk);
            @(negedge clk);
            s_axis_tvalid = 1'b0;
            s_axis_tlast = 1'b0;
        end
    endtask

    task send_parameters;
        integer wi;
        begin
            for (wi = 0; wi < 9; wi = wi + 1) begin
                axis_send_word({24'd0, weight_mem[wi]}, 1'b0);
            end
            axis_send_word(32'd17, 1'b1);
        end
    endtask

    task send_tile;
        begin
            send_count = 0;
            if (CONTINUOUS_INPUT) begin
                @(negedge clk);
                s_axis_tdata = {24'd0, input_mem[0]};
                s_axis_tlast = (INPUT_SIZE == 1);
                s_axis_tvalid = 1'b1;

                while (send_count < INPUT_SIZE) begin
                    @(posedge clk);
                    if (s_axis_tready) begin
                        send_count = send_count + 1;
                    end

                    @(negedge clk);
                    if (send_count < INPUT_SIZE) begin
                        s_axis_tdata = {24'd0, input_mem[send_count]};
                        s_axis_tlast = (send_count == INPUT_SIZE - 1);
                        s_axis_tvalid = 1'b1;
                    end
                    else begin
                        s_axis_tvalid = 1'b0;
                        s_axis_tlast = 1'b0;
                    end
                end
            end
            else begin
                while (send_count < INPUT_SIZE) begin
                    axis_send_word({24'd0, input_mem[send_count]},
                                   send_count == INPUT_SIZE - 1);
                    send_count = send_count + 1;
                end
            end
            send_done = 1;
        end
    endtask

    task receive_tile;
        begin
            recv_count = 0;
            mismatch_count = 0;
            recv_cycle = 0;
            m_axis_tready = 1'b0;

            while (recv_count < OUTPUT_SIZE) begin
                @(negedge clk);
                if (ENABLE_BACKPRESSURE) begin
                    m_axis_tready = ((recv_cycle % 29) >= 11);
                end
                else begin
                    m_axis_tready = 1'b1;
                end
                recv_cycle = recv_cycle + 1;
                @(posedge clk);

                if (m_axis_tvalid && m_axis_tready) begin
                    if ((recv_count == 0) && !send_done) begin
                        first_output_before_send_done = 1;
                    end

                    if ($signed(m_axis_tdata) !== expected_mem[recv_count]) begin
                        if (mismatch_count < 20) begin
                            $display("FAIL: AXI output mismatch index=%0d got=%0d expected=%0d",
                                     recv_count, $signed(m_axis_tdata), expected_mem[recv_count]);
                        end
                        mismatch_count = mismatch_count + 1;
                    end

                    if (m_axis_tlast !== (recv_count == OUTPUT_SIZE - 1)) begin
                        $display("FAIL: AXI TLAST mismatch index=%0d last=%0b",
                                 recv_count, m_axis_tlast);
                        mismatch_count = mismatch_count + 1;
                    end

                    recv_count = recv_count + 1;
                end
            end

            @(negedge clk);
            m_axis_tready = 1'b0;
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
        s_axi_awaddr = 0;
        s_axi_awprot = 0;
        s_axi_awvalid = 0;
        s_axi_wdata = 0;
        s_axi_wstrb = 0;
        s_axi_wvalid = 0;
        s_axi_bready = 0;
        s_axi_araddr = 0;
        s_axi_arprot = 0;
        s_axi_arvalid = 0;
        s_axi_rready = 0;
        s_axis_tdata = 0;
        s_axis_tvalid = 0;
        s_axis_tlast = 0;
        m_axis_tready = 0;
        send_count = 0;
        recv_count = 0;
        send_done = 0;
        first_output_before_send_done = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        // LOAD_PARAM with AW arriving before W.
        axi_write_aw_first(6'h00, 32'h00000008);
        send_parameters();
        axi_read(6'h04, status_value);
        if ((status_value & 32'h00000810) != 32'h00000810) begin
            $display("FAIL: parameter status=0x%08x", status_value);
            $finish;
        end

        axi_write_together(6'h00, 32'h00000002);

        // RUN_TILE with W arriving before AW.
        axi_write_w_first(6'h00, 32'h00000001);

        fork
            send_tile();
            receive_tile();
            begin
                timeout_count = 0;
                while (!irq && timeout_count < 200000) begin
                    @(posedge clk);
                    timeout_count = timeout_count + 1;
                end
            end
        join

        axi_read(6'h04, status_value);
        axi_read(6'h08, input_count_value);
        axi_read(6'h0c, output_count_value);
        axi_read(6'h18, error_value);

        if (!irq) begin
            $display("FAIL: timeout waiting for tile IRQ");
            $finish;
        end
        if (!first_output_before_send_done) begin
            $display("FAIL: tile output did not begin before MM2S input completed");
            $finish;
        end
        if (input_count_value != INPUT_SIZE) begin
            $display("FAIL: stream input count=%0d expected=%0d", input_count_value, INPUT_SIZE);
            $finish;
        end
        if (output_count_value != OUTPUT_SIZE) begin
            $display("FAIL: stream output count=%0d expected=%0d", output_count_value, OUTPUT_SIZE);
            $finish;
        end
        if (error_value != 0) begin
            $display("FAIL: error flags=0x%08x", error_value);
            $finish;
        end
        if (mismatch_count != 0) begin
            $display("FAIL: output mismatches=%0d", mismatch_count);
            $finish;
        end
        if ((status_value & 32'h00000811) != 32'h00000811) begin
            $display("FAIL: final status=0x%08x", status_value);
            $finish;
        end

        $display("PASS: tb_single_conv_tile_axi tile=%0dx%0d inputs=%0d outputs=%0d cycles=%0d backpressure=%0d continuous_input=%0d status=0x%08x",
                 TILE_WIDTH, TILE_HEIGHT, input_count_value, output_count_value,
                 timeout_count, ENABLE_BACKPRESSURE, CONTINUOUS_INPUT,
                 status_value);
        $finish;
    end

endmodule
