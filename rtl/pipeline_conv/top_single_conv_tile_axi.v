`timescale 1ns/1ps

module top_single_conv_tile_axi #(
    parameter DATA_WIDTH        = 8,
    parameter MUL_WIDTH         = 16,
    parameter ACC_WIDTH         = 32,
    parameter TILE_WIDTH        = 28,
    parameter TILE_HEIGHT       = 28,
    parameter OUTPUT_WIDTH      = TILE_WIDTH - 2,
    parameter OUTPUT_HEIGHT     = TILE_HEIGHT - 2,
    parameter INPUT_SIZE        = TILE_WIDTH * TILE_HEIGHT,
    parameter OUTPUT_SIZE       = OUTPUT_WIDTH * OUTPUT_HEIGHT,
    parameter OUTPUT_ADDR_WIDTH = (OUTPUT_SIZE <= 1) ? 1 : $clog2(OUTPUT_SIZE),
    parameter AXI_ADDR_WIDTH     = 6,
    parameter AXI_DATA_WIDTH     = 32,
    parameter OUTPUT_FIFO_DEPTH = 16
)(
    input wire aclk,
    input wire aresetn,

    input wire [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input wire [2:0] s_axi_awprot,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    input wire [AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input wire [(AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    output reg [1:0] s_axi_bresp,
    output reg s_axi_bvalid,
    input wire s_axi_bready,

    input wire [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input wire [2:0] s_axi_arprot,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
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

localparam PARAM_WORDS = 10;

localparam ST_IDLE       = 4'd0;
localparam ST_LOAD_PARAM = 4'd1;
localparam ST_TILE_START = 4'd2;
localparam ST_TILE_RUN   = 4'd3;
localparam ST_TILE_DRAIN = 4'd4;

localparam REG_CTRL          = 4'd0;
localparam REG_STATUS        = 4'd1;
localparam REG_STREAM_IN     = 4'd2;
localparam REG_STREAM_OUT    = 4'd3;
localparam REG_TILE_INPUTS   = 4'd4;
localparam REG_TILE_OUTPUTS  = 4'd5;
localparam REG_ERROR         = 4'd6;
localparam REG_PARAM_WORDS   = 4'd7;

reg [3:0] state_r;
reg [3:0] param_count_r;
reg param_loaded_r;
reg done_sticky_r;
reg [31:0] stream_in_count_r;
reg [31:0] stream_out_count_r;
reg [31:0] error_flags_r;

reg aw_pending_r;
reg [AXI_ADDR_WIDTH-1:0] awaddr_r;
reg w_pending_r;
reg [AXI_DATA_WIDTH-1:0] wdata_r;
reg [(AXI_DATA_WIDTH/8)-1:0] wstrb_r;

wire aw_take_w;
wire w_take_w;
wire write_commit_w;
wire [AXI_ADDR_WIDTH-1:0] write_addr_w;
wire [AXI_DATA_WIDTH-1:0] write_data_w;
wire [(AXI_DATA_WIDTH/8)-1:0] write_strb_w;

wire ctrl_run_tile_w;
wire ctrl_clear_done_w;
wire ctrl_soft_reset_w;
wire ctrl_load_param_w;

wire param_axis_ready_w;
wire core_input_ready_w;
wire axis_accept_w;
wire param_last_word_w;
wire weight_load_en_w;
wire bias_load_en_w;

wire core_resetn_w;
wire core_start_w;
wire signed [ACC_WIDTH-1:0] core_result_data_w;
wire core_result_last_w;
wire core_result_valid_w;
wire core_result_ready_w;
wire core_busy_w;
wire core_done_w;
wire [1:0] core_input_error_w;

localparam FIFO_COUNT_WIDTH = (OUTPUT_FIFO_DEPTH <= 1) ? 1 : $clog2(OUTPUT_FIFO_DEPTH + 1);
wire [FIFO_COUNT_WIDTH-1:0] fifo_level_w;
wire fifo_pop_w;
wire fifo_clear_w;

wire idle_w;
wire loading_w;
wire running_w;
wire outputting_w;
wire [AXI_DATA_WIDTH-1:0] status_w;

assign s_axi_awready = !aw_pending_r && !s_axi_bvalid;
assign s_axi_wready = !w_pending_r && !s_axi_bvalid;
assign s_axi_arready = !s_axi_rvalid;

assign aw_take_w = s_axi_awvalid && s_axi_awready;
assign w_take_w = s_axi_wvalid && s_axi_wready;
assign write_commit_w = !s_axi_bvalid &&
                        (aw_pending_r || aw_take_w) &&
                        (w_pending_r || w_take_w);
assign write_addr_w = aw_pending_r ? awaddr_r : s_axi_awaddr;
assign write_data_w = w_pending_r ? wdata_r : s_axi_wdata;
assign write_strb_w = w_pending_r ? wstrb_r : s_axi_wstrb;

assign ctrl_run_tile_w = write_commit_w && write_strb_w[0] &&
                         (write_addr_w[5:2] == REG_CTRL) && write_data_w[0];
assign ctrl_clear_done_w = write_commit_w && write_strb_w[0] &&
                           (write_addr_w[5:2] == REG_CTRL) && write_data_w[1];
assign ctrl_soft_reset_w = write_commit_w && write_strb_w[0] &&
                           (write_addr_w[5:2] == REG_CTRL) && write_data_w[2];
assign ctrl_load_param_w = write_commit_w && write_strb_w[0] &&
                           (write_addr_w[5:2] == REG_CTRL) && write_data_w[3];

assign param_axis_ready_w = (state_r == ST_LOAD_PARAM);
assign s_axis_tready = param_axis_ready_w ||
                       ((state_r == ST_TILE_RUN) && core_input_ready_w);
assign axis_accept_w = s_axis_tvalid && s_axis_tready;
assign param_last_word_w = (param_count_r == PARAM_WORDS - 1);

assign weight_load_en_w = axis_accept_w && (state_r == ST_LOAD_PARAM) &&
                          (param_count_r < 9);
assign bias_load_en_w = axis_accept_w && (state_r == ST_LOAD_PARAM) &&
                        param_last_word_w;

assign core_resetn_w = aresetn && !ctrl_soft_reset_w;
assign core_start_w = (state_r == ST_TILE_START);

assign fifo_pop_w = m_axis_tvalid && m_axis_tready;
assign fifo_clear_w = ctrl_soft_reset_w ||
                      (ctrl_run_tile_w && (state_r == ST_IDLE) && param_loaded_r);

assign idle_w = (state_r == ST_IDLE);
assign loading_w = (state_r == ST_LOAD_PARAM);
assign running_w = (state_r == ST_TILE_START) ||
                   (state_r == ST_TILE_RUN) ||
                   (state_r == ST_TILE_DRAIN);
assign outputting_w = (fifo_level_w != 0) || (state_r == ST_TILE_DRAIN);

assign status_w = {16'd0,
                   state_r,
                   param_loaded_r,
                   3'd0,
                   core_done_w,
                   core_busy_w,
                   (error_flags_r != 0),
                   done_sticky_r,
                   outputting_w,
                   running_w,
                   loading_w,
                   idle_w};

assign irq = done_sticky_r;

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        aw_pending_r <= 1'b0;
        awaddr_r <= {AXI_ADDR_WIDTH{1'b0}};
        w_pending_r <= 1'b0;
        wdata_r <= {AXI_DATA_WIDTH{1'b0}};
        wstrb_r <= {(AXI_DATA_WIDTH/8){1'b0}};
        s_axi_bresp <= 2'b00;
        s_axi_bvalid <= 1'b0;
        s_axi_rdata <= {AXI_DATA_WIDTH{1'b0}};
        s_axi_rresp <= 2'b00;
        s_axi_rvalid <= 1'b0;
    end
    else begin
        if (aw_take_w) begin
            aw_pending_r <= 1'b1;
            awaddr_r <= s_axi_awaddr;
        end

        if (w_take_w) begin
            w_pending_r <= 1'b1;
            wdata_r <= s_axi_wdata;
            wstrb_r <= s_axi_wstrb;
        end

        if (write_commit_w) begin
            aw_pending_r <= 1'b0;
            w_pending_r <= 1'b0;
            s_axi_bresp <= 2'b00;
            s_axi_bvalid <= 1'b1;
        end
        else if (s_axi_bvalid && s_axi_bready) begin
            s_axi_bvalid <= 1'b0;
        end

        if (s_axi_arvalid && s_axi_arready) begin
            s_axi_rvalid <= 1'b1;
            s_axi_rresp <= 2'b00;

            case (s_axi_araddr[5:2])
                REG_CTRL:         s_axi_rdata <= 32'd0;
                REG_STATUS:       s_axi_rdata <= status_w;
                REG_STREAM_IN:    s_axi_rdata <= stream_in_count_r;
                REG_STREAM_OUT:   s_axi_rdata <= stream_out_count_r;
                REG_TILE_INPUTS:   s_axi_rdata <= INPUT_SIZE;
                REG_TILE_OUTPUTS:  s_axi_rdata <= OUTPUT_SIZE;
                REG_ERROR:        s_axi_rdata <= error_flags_r;
                REG_PARAM_WORDS:   s_axi_rdata <= PARAM_WORDS;
                default:           s_axi_rdata <= 32'd0;
            endcase
        end
        else if (s_axi_rvalid && s_axi_rready) begin
            s_axi_rvalid <= 1'b0;
        end
    end
end

always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
        state_r <= ST_IDLE;
        param_count_r <= 4'd0;
        param_loaded_r <= 1'b0;
        done_sticky_r <= 1'b0;
        stream_in_count_r <= 32'd0;
        stream_out_count_r <= 32'd0;
        error_flags_r <= 32'd0;
    end
    else if (ctrl_soft_reset_w) begin
        state_r <= ST_IDLE;
        param_count_r <= 4'd0;
        done_sticky_r <= 1'b0;
        stream_in_count_r <= 32'd0;
        stream_out_count_r <= 32'd0;
        error_flags_r <= 32'd0;
    end
    else begin
        if (ctrl_clear_done_w) begin
            done_sticky_r <= 1'b0;
        end

        case (state_r)
            ST_IDLE: begin
                if (ctrl_load_param_w) begin
                    state_r <= ST_LOAD_PARAM;
                    param_count_r <= 4'd0;
                    stream_in_count_r <= 32'd0;
                    error_flags_r <= 32'd0;
                    done_sticky_r <= 1'b0;
                end
                else if (ctrl_run_tile_w) begin
                    if (!param_loaded_r) begin
                        error_flags_r[3] <= 1'b1;
                        done_sticky_r <= 1'b1;
                    end
                    else begin
                        state_r <= ST_TILE_START;
                        stream_in_count_r <= 32'd0;
                        stream_out_count_r <= 32'd0;
                        error_flags_r <= 32'd0;
                        done_sticky_r <= 1'b0;
                    end
                end
            end

            ST_LOAD_PARAM: begin
                if (axis_accept_w) begin
                    stream_in_count_r <= stream_in_count_r + 1'b1;

                    if (s_axis_tlast && !param_last_word_w) begin
                        error_flags_r[0] <= 1'b1;
                    end

                    if (param_last_word_w) begin
                        if (!s_axis_tlast) begin
                            error_flags_r[1] <= 1'b1;
                        end
                        param_loaded_r <= 1'b1;
                        done_sticky_r <= 1'b1;
                        state_r <= ST_IDLE;
                    end
                    else begin
                        param_count_r <= param_count_r + 1'b1;
                    end
                end
            end

            ST_TILE_START: begin
                state_r <= ST_TILE_RUN;
            end

            ST_TILE_RUN: begin
                if (axis_accept_w) begin
                    stream_in_count_r <= stream_in_count_r + 1'b1;
                end

                error_flags_r[5:4] <= core_input_error_w;

                if (core_done_w) begin
                    state_r <= ST_TILE_DRAIN;
                end
            end

            ST_TILE_DRAIN: begin
                error_flags_r[5:4] <= core_input_error_w;
            end

            default: begin
                state_r <= ST_IDLE;
            end
        endcase

        if (fifo_pop_w) begin
            stream_out_count_r <= stream_out_count_r + 1'b1;

            if (m_axis_tlast) begin
                if (stream_out_count_r != OUTPUT_SIZE - 1) begin
                    error_flags_r[2] <= 1'b1;
                end
                done_sticky_r <= 1'b1;
                state_r <= ST_IDLE;
            end
        end

        if ((ctrl_run_tile_w || ctrl_load_param_w) && (state_r != ST_IDLE)) begin
            error_flags_r[3] <= 1'b1;
        end
    end
end

top_single_conv_tile #(
    .DATA_WIDTH(DATA_WIDTH),
    .MUL_WIDTH(MUL_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .TILE_WIDTH(TILE_WIDTH),
    .TILE_HEIGHT(TILE_HEIGHT),
    .OUTPUT_WIDTH(OUTPUT_WIDTH),
    .OUTPUT_HEIGHT(OUTPUT_HEIGHT),
    .OUTPUT_SIZE(OUTPUT_SIZE),
    .OUTPUT_ADDR_WIDTH(OUTPUT_ADDR_WIDTH)
) u_tile_core (
    .clk(aclk),
    .rst_n(core_resetn_w),
    .start_i(core_start_w),
    .s_data_i(s_axis_tdata[DATA_WIDTH-1:0]),
    .s_valid_i(s_axis_tvalid && (state_r == ST_TILE_RUN)),
    .s_ready_o(core_input_ready_w),
    .s_last_i(s_axis_tlast),
    .weight_load_en_i(weight_load_en_w),
    .weight_load_addr_i(param_count_r),
    .weight_load_data_i(s_axis_tdata[DATA_WIDTH-1:0]),
    .bias_load_en_i(bias_load_en_w),
    .bias_load_data_i(s_axis_tdata[ACC_WIDTH-1:0]),
    .result_data_o(core_result_data_w),
    .result_addr_o(),
    .result_last_o(core_result_last_w),
    .result_valid_o(core_result_valid_w),
    .result_ready_i(core_result_ready_w),
    .busy_o(core_busy_w),
    .done_o(core_done_w),
    .input_error_o(core_input_error_w),
    .state_o()
);

axis_output_fifo #(
    .DATA_WIDTH(AXI_DATA_WIDTH),
    .DEPTH(OUTPUT_FIFO_DEPTH)
) u_output_fifo (
    .clk(aclk),
    .rst_n(aresetn),
    .clear_i(fifo_clear_w),
    .s_data_i(core_result_data_w[AXI_DATA_WIDTH-1:0]),
    .s_last_i(core_result_last_w),
    .s_valid_i(core_result_valid_w),
    .s_ready_o(core_result_ready_w),
    .m_data_o(m_axis_tdata),
    .m_last_o(m_axis_tlast),
    .m_valid_o(m_axis_tvalid),
    .m_ready_i(m_axis_tready),
    .level_o(fifo_level_w)
);

endmodule
