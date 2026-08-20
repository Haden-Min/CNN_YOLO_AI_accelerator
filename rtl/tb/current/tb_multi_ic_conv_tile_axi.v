`timescale 1ns/1ps

module tb_multi_ic_conv_tile_axi;

localparam TILE_WIDTH = 6;
localparam TILE_HEIGHT = 6;
localparam OUTPUT_WIDTH = TILE_WIDTH - 2;
localparam OUTPUT_HEIGHT = TILE_HEIGHT - 2;
localparam INPUT_SIZE = TILE_WIDTH * TILE_HEIGHT;
localparam OUTPUT_SIZE = OUTPUT_WIDTH * OUTPUT_HEIGHT;
localparam INPUT_CHANNELS = 3;
localparam OUTPUT_ADDR_WIDTH = $clog2(OUTPUT_SIZE);

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

reg signed [7:0] input_mem [0:INPUT_CHANNELS*INPUT_SIZE-1];
reg signed [7:0] weight_mem [0:INPUT_CHANNELS*9-1];
reg signed [31:0] expected_mem [0:OUTPUT_SIZE-1];

integer ch;
integer x;
integer y;
integer kx;
integer ky;
integer idx;
integer sum;
integer recv_count;
integer mismatch_count;
integer timeout_count;
integer status_value;
integer current_ic_value;
integer total_ic_value;
integer input_count_value;
integer output_count_value;
integer error_value;

top_single_conv_tile_axi #(
    .TILE_WIDTH(TILE_WIDTH),
    .TILE_HEIGHT(TILE_HEIGHT),
    .OUTPUT_WIDTH(OUTPUT_WIDTH),
    .OUTPUT_HEIGHT(OUTPUT_HEIGHT),
    .INPUT_SIZE(INPUT_SIZE),
    .OUTPUT_SIZE(OUTPUT_SIZE),
    .OUTPUT_ADDR_WIDTH(OUTPUT_ADDR_WIDTH),
    .OUTPUT_FIFO_DEPTH(4),
    .MAX_INPUT_CHANNELS(1024)
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

task axi_write;
    input [5:0] addr;
    input [31:0] data;
    begin
        @(negedge clk);
        s_axi_awaddr = addr;
        s_axi_awvalid = 1'b1;
        s_axi_wdata = data;
        s_axi_wstrb = 4'hf;
        s_axi_wvalid = 1'b1;

        @(posedge clk);
        while (!(s_axi_awready && s_axi_wready)) @(posedge clk);

        @(negedge clk);
        s_axi_awvalid = 1'b0;
        s_axi_wvalid = 1'b0;
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
    input integer channel;
    integer wi;
    begin
        for (wi = 0; wi < 9; wi = wi + 1) begin
            axis_send_word({24'd0, weight_mem[channel*9 + wi]}, 1'b0);
        end

        // Only channel zero's bias may affect the layer result. Deliberately
        // send different later values to catch accidental repeated bias adds.
        if (channel == 0) begin
            axis_send_word(32'd17, 1'b1);
        end
        else begin
            axis_send_word(32'd1000 + channel, 1'b1);
        end
    end
endtask

task send_tile;
    input integer channel;
    integer input_index;
    begin
        for (input_index = 0; input_index < INPUT_SIZE;
             input_index = input_index + 1) begin
            axis_send_word(
                {24'd0, input_mem[channel*INPUT_SIZE + input_index]},
                input_index == INPUT_SIZE - 1
            );
        end
    end
endtask

task wait_for_irq;
    begin
        timeout_count = 0;
        while (!irq && timeout_count < 100000) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end

        if (!irq) begin
            $display("FAIL: timeout waiting for IRQ");
            $finish;
        end
    end
endtask

task receive_results;
    integer ready_cycle;
    begin
        recv_count = 0;
        ready_cycle = 0;

        while (recv_count < OUTPUT_SIZE) begin
            @(negedge clk);
            m_axis_tready = ((ready_cycle % 7) >= 2);
            ready_cycle = ready_cycle + 1;
            @(posedge clk);

            if (m_axis_tvalid && m_axis_tready) begin
                if ($signed(m_axis_tdata) !== expected_mem[recv_count]) begin
                    $display("FAIL: output[%0d] got=%0d expected=%0d",
                             recv_count, $signed(m_axis_tdata),
                             expected_mem[recv_count]);
                    mismatch_count = mismatch_count + 1;
                end

                if (m_axis_tlast !== (recv_count == OUTPUT_SIZE - 1)) begin
                    $display("FAIL: TLAST mismatch at output %0d", recv_count);
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
    for (ch = 0; ch < INPUT_CHANNELS; ch = ch + 1) begin
        for (y = 0; y < TILE_HEIGHT; y = y + 1) begin
            for (x = 0; x < TILE_WIDTH; x = x + 1) begin
                input_mem[ch*INPUT_SIZE + y*TILE_WIDTH + x] =
                    ((ch*11 + y*7 + x*3 + 5) % 23) - 11;
            end
        end

        for (idx = 0; idx < 9; idx = idx + 1) begin
            weight_mem[ch*9 + idx] = ((ch*5 + idx*3 + 1) % 9) - 4;
        end
    end

    for (y = 0; y < OUTPUT_HEIGHT; y = y + 1) begin
        for (x = 0; x < OUTPUT_WIDTH; x = x + 1) begin
            sum = 17;
            for (ch = 0; ch < INPUT_CHANNELS; ch = ch + 1) begin
                for (ky = 0; ky < 3; ky = ky + 1) begin
                    for (kx = 0; kx < 3; kx = kx + 1) begin
                        sum = sum +
                            input_mem[ch*INPUT_SIZE +
                                      (y+ky)*TILE_WIDTH + (x+kx)] *
                            weight_mem[ch*9 + ky*3 + kx];
                    end
                end
            end
            expected_mem[y*OUTPUT_WIDTH + x] = sum;
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
    recv_count = 0;
    mismatch_count = 0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (3) @(posedge clk);

    // Configure the number of serial input-channel passes.
    axi_write(6'h20, INPUT_CHANNELS);
    axi_read(6'h20, total_ic_value);
    if (total_ic_value != INPUT_CHANNELS) begin
        $display("FAIL: TOTAL_IC=%0d expected=%0d",
                 total_ic_value, INPUT_CHANNELS);
        $finish;
    end

    for (ch = 0; ch < INPUT_CHANNELS; ch = ch + 1) begin
        axi_write(6'h00, 32'h00000008);
        send_parameters(ch);
        wait_for_irq();
        axi_write(6'h00, 32'h00000002);

        axi_write(6'h00, 32'h00000001);

        if (ch == INPUT_CHANNELS - 1) begin
            fork
                send_tile(ch);
                receive_results();
                wait_for_irq();
            join
        end
        else begin
            send_tile(ch);
            wait_for_irq();

            if (m_axis_tvalid) begin
                $display("FAIL: intermediate channel produced AXI output");
                $finish;
            end

            axi_read(6'h24, current_ic_value);
            if (current_ic_value != ch + 1) begin
                $display("FAIL: CURRENT_IC=%0d expected=%0d",
                         current_ic_value, ch + 1);
                $finish;
            end

            axi_read(6'h0c, output_count_value);
            if (output_count_value != 0) begin
                $display("FAIL: intermediate output count=%0d",
                         output_count_value);
                $finish;
            end
        end
    end

    axi_read(6'h04, status_value);
    axi_read(6'h08, input_count_value);
    axi_read(6'h0c, output_count_value);
    axi_read(6'h18, error_value);

    if (recv_count != OUTPUT_SIZE) begin
        $display("FAIL: output count=%0d expected=%0d", recv_count, OUTPUT_SIZE);
        $finish;
    end
    if (input_count_value != INPUT_SIZE) begin
        $display("FAIL: final input count=%0d expected=%0d",
                 input_count_value, INPUT_SIZE);
        $finish;
    end
    if (output_count_value != OUTPUT_SIZE) begin
        $display("FAIL: stream output count=%0d expected=%0d",
                 output_count_value, OUTPUT_SIZE);
        $finish;
    end
    if (error_value != 0) begin
        $display("FAIL: error flags=0x%08x", error_value);
        $finish;
    end
    if (mismatch_count != 0) begin
        $display("FAIL: mismatches=%0d", mismatch_count);
        $finish;
    end
    if ((status_value & 32'h00000811) != 32'h00000811) begin
        $display("FAIL: final status=0x%08x", status_value);
        $finish;
    end

    $display("PASS: tb_multi_ic_conv_tile_axi channels=%0d tile=%0dx%0d outputs=%0d status=0x%08x",
             INPUT_CHANNELS, TILE_WIDTH, TILE_HEIGHT, recv_count, status_value);
    $finish;
end

endmodule
