`timescale 1ns/1ps

module top_single_conv_pipeline_axi #(
    parameter DATA_WIDTH = 8,
    parameter MUL_WIDTH  = 16,
    parameter ACC_WIDTH  = 32,
    parameter ACC_BANK_SIZE = 9,

    parameter IC      = 1,
    parameter OC      = 1,
    parameter IN_H    = 416,
    parameter IN_W    = 416,
    parameter K_H     = 3,
    parameter K_W     = 3,
    parameter STRIDE  = 1,
    parameter PADDING = 0,
    parameter OUT_H   = 414,
    parameter OUT_W   = 414,

    parameter INPUT_SIZE  = IC * IN_H * IN_W,
    parameter WEIGHT_SIZE = OC * IC * K_H * K_W,
    parameter BIAS_SIZE   = OC,
    parameter OUTPUT_SIZE = OC * OUT_H * OUT_W,

    parameter INPUT_ADDR_WIDTH  = (INPUT_SIZE  <= 1) ? 1 : $clog2(INPUT_SIZE),
    parameter WEIGHT_ADDR_WIDTH = (WEIGHT_SIZE <= 1) ? 1 : $clog2(WEIGHT_SIZE),
    parameter BIAS_ADDR_WIDTH   = (BIAS_SIZE   <= 1) ? 1 : $clog2(BIAS_SIZE),
    parameter OUTPUT_ADDR_WIDTH = (OUTPUT_SIZE <= 1) ? 1 : $clog2(OUTPUT_SIZE),

    parameter AXI_ADDR_WIDTH = 6,
    parameter AXI_DATA_WIDTH = 32
)(
    input wire aclk,
    input wire aresetn,

    input wire [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input wire [2:0] s_axi_awprot,
    input wire s_axi_awvalid,
    output reg s_axi_awready,
    input wire [AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input wire [(AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output reg s_axi_wready,
    output reg [1:0] s_axi_bresp,
    output reg s_axi_bvalid,
    input wire s_axi_bready,
    input wire [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input wire [2:0] s_axi_arprot,
    input wire s_axi_arvalid,
    output reg s_axi_arready,
    output reg [AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output reg [1:0] s_axi_rresp,
    output reg s_axi_rvalid,
    input wire s_axi_rready,

    input wire [AXI_DATA_WIDTH-1:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output wire s_axis_tready,
    input wire s_axis_tlast,

    output wire [AXI_DATA_WIDTH-1:0] m_axis_tdata,
    output wire m_axis_tvalid,
    input wire m_axis_tready,
    output wire m_axis_tlast,

    output wire irq
);

localparam INPUT_ROW_WORDS       = IC * IN_W;
localparam INITIAL_INPUT_WORDS   = IC * K_H * IN_W;
localparam EXPECTED_INPUT_WORDS  = INPUT_SIZE + WEIGHT_SIZE + BIAS_SIZE;

localparam ST_IDLE         = 4'd0;
localparam ST_LOAD_INITIAL = 4'd1;
localparam ST_LOAD_WEIGHT  = 4'd2;
localparam ST_LOAD_BIAS    = 4'd3;
localparam ST_START        = 4'd4;
localparam ST_RUN          = 4'd5;
localparam ST_LOAD_ROW     = 4'd6;
localparam ST_OUT_PREP     = 4'd7;
localparam ST_OUT_WAIT     = 4'd8;
localparam ST_OUT_CAPTURE  = 4'd9;
localparam ST_OUT_SEND     = 4'd10;
localparam ST_DONE         = 4'd11;

localparam REG_CTRL        = 4'd0;
localparam REG_STATUS      = 4'd1;
localparam REG_STREAM_IN   = 4'd2;
localparam REG_STREAM_OUT  = 4'd3;
localparam REG_EXPECTED_IN = 4'd4;
localparam REG_EXPECTED_OUT= 4'd5;
localparam REG_ERROR       = 4'd6;

reg [3:0] state_r;
reg [31:0] load_count_r;
reg [31:0] row_count_r;
reg [31:0] next_input_row_r;
reg [31:0] stream_in_count_r;
reg [31:0] stream_out_count_r;
reg [31:0] error_flags_r;
reg done_sticky_r;

reg [AXI_ADDR_WIDTH-1:0] awaddr_r;
reg [AXI_DATA_WIDTH-1:0] wdata_r;
reg [(AXI_DATA_WIDTH/8)-1:0] wstrb_r;
reg aw_have_r;
reg w_have_r;

reg core_start_r;
reg input_load_en_r;
reg [INPUT_ADDR_WIDTH-1:0] input_load_addr_r;
reg signed [DATA_WIDTH-1:0] input_load_data_r;
reg weight_load_en_r;
reg [WEIGHT_ADDR_WIDTH-1:0] weight_load_addr_r;
reg signed [DATA_WIDTH-1:0] weight_load_data_r;
reg bias_load_en_r;
reg [BIAS_ADDR_WIDTH-1:0] bias_load_addr_r;
reg signed [ACC_WIDTH-1:0] bias_load_data_r;
reg [OUTPUT_ADDR_WIDTH-1:0] output_read_addr_r;

wire [BIAS_ADDR_WIDTH-1:0] core_bias_addr_w;
wire [OUTPUT_ADDR_WIDTH-1:0] core_output_addr_w;
wire core_output_we_w;
wire core_busy_w;
wire core_done_w;
wire signed [ACC_WIDTH-1:0] core_output_data_w;
wire signed [ACC_WIDTH-1:0] core_output_read_data_w;

reg [AXI_DATA_WIDTH-1:0] m_axis_tdata_r;
reg m_axis_tvalid_r;
reg m_axis_tlast_r;

wire write_ready_w;
wire aw_fire_w;
wire w_fire_w;
wire write_do_w;
wire [AXI_ADDR_WIDTH-1:0] write_addr_w;
wire [AXI_DATA_WIDTH-1:0] write_data_w;
wire [(AXI_DATA_WIDTH/8)-1:0] write_strb_w;
wire ctrl_start_w;
wire ctrl_clear_done_w;
wire ctrl_soft_reset_w;

wire axis_load_state_w;
wire axis_accept_w;
wire axis_final_word_w;
wire [31:0] row_base_addr_w;
wire [31:0] input_row_write_addr_w;
wire [31:0] row_done_addr_w;
wire row_done_match_w;
wire idle_w;
wire loading_w;
wire running_w;
wire outputting_w;
wire [AXI_DATA_WIDTH-1:0] status_w;

assign write_ready_w = !s_axi_bvalid;
assign aw_fire_w = write_ready_w && s_axi_awvalid && s_axi_wvalid;
assign w_fire_w = write_ready_w && s_axi_awvalid && s_axi_wvalid;
assign write_do_w = write_ready_w && s_axi_awvalid && s_axi_wvalid;
assign write_addr_w = s_axi_awaddr;
assign write_data_w = s_axi_wdata;
assign write_strb_w = s_axi_wstrb;

assign ctrl_start_w = write_do_w && (write_addr_w[5:2] == REG_CTRL) && write_data_w[0];
assign ctrl_clear_done_w = write_do_w && (write_addr_w[5:2] == REG_CTRL) && write_data_w[1];
assign ctrl_soft_reset_w = write_do_w && (write_addr_w[5:2] == REG_CTRL) && write_data_w[2];

assign axis_load_state_w = (state_r == ST_LOAD_INITIAL) ||
                           (state_r == ST_LOAD_WEIGHT)  ||
                           (state_r == ST_LOAD_BIAS)    ||
                           (state_r == ST_LOAD_ROW);
assign s_axis_tready = axis_load_state_w;
assign axis_accept_w = s_axis_tvalid && s_axis_tready;
assign axis_final_word_w = (state_r == ST_LOAD_ROW) &&
                           (next_input_row_r == (IN_H - 1)) &&
                           (row_count_r == (INPUT_ROW_WORDS - 1));

assign row_base_addr_w = next_input_row_r * INPUT_ROW_WORDS;
assign input_row_write_addr_w = row_base_addr_w + row_count_r;
assign row_done_addr_w = (next_input_row_r - K_H) * OUT_W + (OUT_W - 1);
assign row_done_match_w = (next_input_row_r < IN_H) &&
                          core_output_we_w &&
                          (core_output_addr_w == row_done_addr_w[OUTPUT_ADDR_WIDTH-1:0]);

assign idle_w = (state_r == ST_IDLE) || (state_r == ST_DONE);
assign loading_w = (state_r == ST_LOAD_INITIAL) ||
                   (state_r == ST_LOAD_WEIGHT)  ||
                   (state_r == ST_LOAD_BIAS);
assign running_w = (state_r == ST_RUN) || (state_r == ST_LOAD_ROW);
assign outputting_w = (state_r == ST_OUT_PREP) ||
                      (state_r == ST_OUT_WAIT) ||
                      (state_r == ST_OUT_CAPTURE) ||
                      (state_r == ST_OUT_SEND);
assign status_w = {{(AXI_DATA_WIDTH-16){1'b0}},
                   state_r,
                   4'd0,
                   core_done_w,
                   core_busy_w,
                   (error_flags_r != 32'd0),
                   done_sticky_r,
                   outputting_w,
                   running_w,
                   loading_w,
                   idle_w};

assign m_axis_tdata = m_axis_tdata_r;
assign m_axis_tvalid = m_axis_tvalid_r;
assign m_axis_tlast = m_axis_tlast_r;
assign irq = done_sticky_r;

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        state_r <= ST_IDLE;
        load_count_r <= 32'd0;
        row_count_r <= 32'd0;
        next_input_row_r <= 32'd0;
        stream_in_count_r <= 32'd0;
        stream_out_count_r <= 32'd0;
        error_flags_r <= 32'd0;
        done_sticky_r <= 1'b0;

        awaddr_r <= {AXI_ADDR_WIDTH{1'b0}};
        wdata_r <= {AXI_DATA_WIDTH{1'b0}};
        wstrb_r <= {(AXI_DATA_WIDTH/8){1'b0}};
        aw_have_r <= 1'b0;
        w_have_r <= 1'b0;
        s_axi_awready <= 1'b0;
        s_axi_wready <= 1'b0;
        s_axi_bresp <= 2'b00;
        s_axi_bvalid <= 1'b0;
        s_axi_arready <= 1'b0;
        s_axi_rdata <= {AXI_DATA_WIDTH{1'b0}};
        s_axi_rresp <= 2'b00;
        s_axi_rvalid <= 1'b0;

        core_start_r <= 1'b0;
        input_load_en_r <= 1'b0;
        input_load_addr_r <= {INPUT_ADDR_WIDTH{1'b0}};
        input_load_data_r <= {DATA_WIDTH{1'b0}};
        weight_load_en_r <= 1'b0;
        weight_load_addr_r <= {WEIGHT_ADDR_WIDTH{1'b0}};
        weight_load_data_r <= {DATA_WIDTH{1'b0}};
        bias_load_en_r <= 1'b0;
        bias_load_addr_r <= {BIAS_ADDR_WIDTH{1'b0}};
        bias_load_data_r <= {ACC_WIDTH{1'b0}};
        output_read_addr_r <= {OUTPUT_ADDR_WIDTH{1'b0}};

        m_axis_tdata_r <= {AXI_DATA_WIDTH{1'b0}};
        m_axis_tvalid_r <= 1'b0;
        m_axis_tlast_r <= 1'b0;
    end
    else begin
        s_axi_awready <= aw_fire_w;
        s_axi_wready <= w_fire_w;
        s_axi_arready <= (!s_axi_rvalid && s_axi_arvalid);
        core_start_r <= 1'b0;
        input_load_en_r <= 1'b0;
        weight_load_en_r <= 1'b0;
        bias_load_en_r <= 1'b0;

        awaddr_r <= write_addr_w;
        wdata_r <= write_data_w;
        wstrb_r <= write_strb_w;
        aw_have_r <= 1'b0;
        w_have_r <= 1'b0;

        if (write_do_w) begin
            s_axi_bvalid <= 1'b1;
            s_axi_bresp <= 2'b00;
        end
        else if (s_axi_bvalid && s_axi_bready) begin
            s_axi_bvalid <= 1'b0;
        end

        if (!s_axi_rvalid && s_axi_arvalid) begin
            s_axi_rvalid <= 1'b1;
            s_axi_rresp <= 2'b00;
            case (s_axi_araddr[5:2])
                REG_CTRL:         s_axi_rdata <= {{(AXI_DATA_WIDTH-1){1'b0}}, (state_r != ST_IDLE)};
                REG_STATUS:       s_axi_rdata <= status_w;
                REG_STREAM_IN:    s_axi_rdata <= stream_in_count_r[AXI_DATA_WIDTH-1:0];
                REG_STREAM_OUT:   s_axi_rdata <= done_sticky_r ? OUTPUT_SIZE : stream_out_count_r[AXI_DATA_WIDTH-1:0];
                REG_EXPECTED_IN:  s_axi_rdata <= EXPECTED_INPUT_WORDS;
                REG_EXPECTED_OUT: s_axi_rdata <= OUTPUT_SIZE;
                REG_ERROR:        s_axi_rdata <= error_flags_r[AXI_DATA_WIDTH-1:0];
                default:          s_axi_rdata <= {AXI_DATA_WIDTH{1'b0}};
            endcase
        end
        else if (s_axi_rvalid && s_axi_rready) begin
            s_axi_rvalid <= 1'b0;
        end

        if (ctrl_clear_done_w) begin
            done_sticky_r <= 1'b0;
        end

        if (ctrl_soft_reset_w) begin
            state_r <= ST_IDLE;
            load_count_r <= 32'd0;
            row_count_r <= 32'd0;
            next_input_row_r <= 32'd0;
            stream_in_count_r <= 32'd0;
            stream_out_count_r <= 32'd0;
            error_flags_r <= 32'd0;
            done_sticky_r <= 1'b0;
            m_axis_tvalid_r <= 1'b0;
            m_axis_tlast_r <= 1'b0;
        end
        else begin
            if (axis_accept_w) begin
                stream_in_count_r <= stream_in_count_r + 32'd1;
                if (s_axis_tlast && !axis_final_word_w) begin
                    error_flags_r[0] <= 1'b1;
                end
                if (axis_final_word_w && s_axis_tlast) begin
                    error_flags_r[1] <= 1'b0;
                end
            end

            case (state_r)
                ST_IDLE: begin
                    m_axis_tvalid_r <= 1'b0;
                    m_axis_tlast_r <= 1'b0;
                    if (ctrl_start_w) begin
                        state_r <= ST_LOAD_INITIAL;
                        load_count_r <= 32'd0;
                        row_count_r <= 32'd0;
                        next_input_row_r <= K_H;
                        stream_in_count_r <= 32'd0;
                        stream_out_count_r <= 32'd0;
                        error_flags_r <= 32'd0;
                        done_sticky_r <= 1'b0;
                    end
                end

                ST_LOAD_INITIAL: begin
                    if (axis_accept_w) begin
                        input_load_en_r <= 1'b1;
                        input_load_addr_r <= load_count_r[INPUT_ADDR_WIDTH-1:0];
                        input_load_data_r <= s_axis_tdata[DATA_WIDTH-1:0];
                        if (load_count_r == (INITIAL_INPUT_WORDS - 1)) begin
                            state_r <= ST_LOAD_WEIGHT;
                            load_count_r <= 32'd0;
                        end
                        else begin
                            load_count_r <= load_count_r + 32'd1;
                        end
                    end
                end

                ST_LOAD_WEIGHT: begin
                    if (axis_accept_w) begin
                        weight_load_en_r <= 1'b1;
                        weight_load_addr_r <= load_count_r[WEIGHT_ADDR_WIDTH-1:0];
                        weight_load_data_r <= s_axis_tdata[DATA_WIDTH-1:0];
                        if (load_count_r == (WEIGHT_SIZE - 1)) begin
                            state_r <= ST_LOAD_BIAS;
                            load_count_r <= 32'd0;
                        end
                        else begin
                            load_count_r <= load_count_r + 32'd1;
                        end
                    end
                end

                ST_LOAD_BIAS: begin
                    if (axis_accept_w) begin
                        bias_load_en_r <= 1'b1;
                        bias_load_addr_r <= load_count_r[BIAS_ADDR_WIDTH-1:0];
                        bias_load_data_r <= s_axis_tdata[ACC_WIDTH-1:0];
                        if (load_count_r == (BIAS_SIZE - 1)) begin
                            state_r <= ST_START;
                            load_count_r <= 32'd0;
                        end
                        else begin
                            load_count_r <= load_count_r + 32'd1;
                        end
                    end
                end

                ST_START: begin
                    core_start_r <= 1'b1;
                    state_r <= ST_RUN;
                end

                ST_RUN: begin
                    if (row_done_match_w) begin
                        state_r <= ST_LOAD_ROW;
                        row_count_r <= 32'd0;
                    end
                    else if (core_done_w && (next_input_row_r >= IN_H)) begin
                        state_r <= ST_OUT_PREP;
                        stream_out_count_r <= 32'd0;
                        output_read_addr_r <= {OUTPUT_ADDR_WIDTH{1'b0}};
                    end
                end

                ST_LOAD_ROW: begin
                    if (axis_accept_w) begin
                        input_load_en_r <= 1'b1;
                        input_load_addr_r <= input_row_write_addr_w[INPUT_ADDR_WIDTH-1:0];
                        input_load_data_r <= s_axis_tdata[DATA_WIDTH-1:0];
                        if (row_count_r == (INPUT_ROW_WORDS - 1)) begin
                            row_count_r <= 32'd0;
                            next_input_row_r <= next_input_row_r + 32'd1;
                            state_r <= ST_RUN;
                        end
                        else begin
                            row_count_r <= row_count_r + 32'd1;
                        end
                    end
                end

                ST_OUT_PREP: begin
                    output_read_addr_r <= stream_out_count_r[OUTPUT_ADDR_WIDTH-1:0];
                    state_r <= ST_OUT_WAIT;
                end

                ST_OUT_WAIT: begin
                    state_r <= ST_OUT_CAPTURE;
                end

                ST_OUT_CAPTURE: begin
                    m_axis_tdata_r <= core_output_read_data_w[AXI_DATA_WIDTH-1:0];
                    m_axis_tvalid_r <= 1'b1;
                    m_axis_tlast_r <= (stream_out_count_r == (OUTPUT_SIZE - 1));
                    state_r <= ST_OUT_SEND;
                end

                ST_OUT_SEND: begin
                    if (m_axis_tvalid_r && m_axis_tready) begin
                        m_axis_tvalid_r <= 1'b0;
                        if (m_axis_tlast_r) begin
                            stream_out_count_r <= OUTPUT_SIZE;
                            m_axis_tlast_r <= 1'b0;
                            done_sticky_r <= 1'b1;
                            state_r <= ST_DONE;
                        end
                        else begin
                            stream_out_count_r <= stream_out_count_r + 32'd1;
                            state_r <= ST_OUT_PREP;
                        end
                    end
                end

                ST_DONE: begin
                    if (ctrl_start_w) begin
                        state_r <= ST_LOAD_INITIAL;
                        load_count_r <= 32'd0;
                        row_count_r <= 32'd0;
                        next_input_row_r <= K_H;
                        stream_in_count_r <= 32'd0;
                        stream_out_count_r <= 32'd0;
                        error_flags_r <= 32'd0;
                        done_sticky_r <= 1'b0;
                    end
                end

                default: begin
                    state_r <= ST_IDLE;
                end
            endcase
        end
    end
end

top_single_conv_pipeline #(
    .DATA_WIDTH(DATA_WIDTH),
    .MUL_WIDTH(MUL_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .ACC_BANK_SIZE(ACC_BANK_SIZE),
    .IC(IC),
    .OC(OC),
    .IN_H(IN_H),
    .IN_W(IN_W),
    .K_H(K_H),
    .K_W(K_W),
    .STRIDE(STRIDE),
    .PADDING(PADDING),
    .OUT_H(OUT_H),
    .OUT_W(OUT_W),
    .INPUT_SIZE(INPUT_SIZE),
    .WEIGHT_SIZE(WEIGHT_SIZE),
    .BIAS_SIZE(BIAS_SIZE),
    .OUTPUT_SIZE(OUTPUT_SIZE),
    .INPUT_ADDR_WIDTH(INPUT_ADDR_WIDTH),
    .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
    .BIAS_ADDR_WIDTH(BIAS_ADDR_WIDTH),
    .OUTPUT_ADDR_WIDTH(OUTPUT_ADDR_WIDTH)
) u_core (
    .clk(aclk),
    .rst_n(aresetn),
    .start_i(core_start_r),
    .input_load_en_i(input_load_en_r),
    .input_load_addr_i(input_load_addr_r),
    .input_stream_data_i(input_load_data_r),
    .weight_load_en_i(weight_load_en_r),
    .weight_load_addr_i(weight_load_addr_r),
    .weight_stream_data_i(weight_load_data_r),
    .bias_load_en_i(bias_load_en_r),
    .bias_load_addr_i(bias_load_addr_r),
    .bias_load_data_i(bias_load_data_r),
    .output_read_addr_i(output_read_addr_r),
    .bias_addr_o(core_bias_addr_w),
    .output_addr_o(core_output_addr_w),
    .output_we_o(core_output_we_w),
    .busy_o(core_busy_w),
    .done_o(core_done_w),
    .output_data_o(core_output_data_w),
    .output_read_data_o(core_output_read_data_w)
);

endmodule
