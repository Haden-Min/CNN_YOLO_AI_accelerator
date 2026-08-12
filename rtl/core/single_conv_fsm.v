`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// DUT instance
// -----------------------------------------------------------------------------
/*
single_conv_fsm #(
    .DATA_WIDTH (TB_DATA_WIDTH)     ,
    .ACC_WIDTH  (TB_ACC_WIDTH)      ,

    .IC         (TB_IC)             ,
    .OC         (TB_OC)             ,

    .IN_H       (TB_IN_H)           ,
    .IN_W       (TB_IN_W)           ,

    .K_H        (TB_K_H)            ,
    .K_W        (TB_K_W)            ,

    .STRIDE     (TB_STRIDE)         ,
    .PADDING    (TB_PADDING)        ,

    .OUT_H      (TB_OUT_H)          ,
    .OUT_W      (TB_OUT_W)
) u_single_conv_fsm (
    .clk_i           (clk_i)        ,
    .rst_n           (rst_n)        ,
    .start_i         (start_i)      ,

    .input_addr_o    (input_addr_o) ,
    .weight_addr_o   (weight_addr_o),
    .bias_addr_o     (bias_addr_o)  ,
    .output_addr_o   (output_addr_o),

    .busy_o          (busy_o)       ,
    .done_o          (done_o)       ,
    .output_we_o     (output_we_o)  ,
    .mac_en_o        (mac_en_o)     ,
    .acc_load_bias_o (acc_load_bias_o)
);
*/

module single_conv_fsm #(
    parameter   DATA_WIDTH  = 8         ,   // INT8 Data
    parameter   ACC_WIDTH   = 32        ,   // Accumulator's output data size is INT32

    parameter   IC          = 1         ,   // # of Input Channel
    parameter   OC          = 1         ,   // # of Output Channel

    parameter   IN_H        = 5         ,   // Input Height
    parameter   IN_W        = 5         ,   // Input Width

    parameter   K_H         = 3         ,   // Kernel Height
    parameter   K_W         = 3         ,   // Kernel Width

    parameter   STRIDE      = 1         ,   // stride
    parameter   PADDING     = 0         ,   // padding

    parameter   OUT_H       = 3         ,   // Output Height
    parameter   OUT_W       = 3         ,   // Output width

    parameter   PARALLEL_KERNEL = 0     ,   // 0: scalar kh/kw MAC loop, 1: one MAC per 3x3 kernel window

    // Data size calculation
    parameter   INPUT_SIZE  = IC * IN_H * IN_W      ,
    parameter   WEIGHT_SIZE = OC * IC * K_H * K_W   ,
    parameter   BIAS_SIZE   = OC                    ,
    parameter   OUTPUT_SIZE = OC * OUT_H * OUT_W    ,

    // Address width calculation
    parameter   INPUT_ADDR_WIDTH    = (INPUT_SIZE   <= 1) ? 1 : $clog2(INPUT_SIZE)  ,
    parameter   WEIGHT_ADDR_WIDTH   = (WEIGHT_SIZE  <= 1) ? 1 : $clog2(WEIGHT_SIZE) ,
    parameter   BIAS_ADDR_WIDTH     = (BIAS_SIZE    <= 1) ? 1 : $clog2(BIAS_SIZE)   ,
    parameter   OUT_ADDR_WIDTH      = (OUTPUT_SIZE  <= 1) ? 1 : $clog2(OUTPUT_SIZE)
)(
    // system interface
    input   wire        clk_i           ,
    input   wire        rst_n           ,
    input   wire        start_i         ,
    input   wire        input_window_valid_i,
    input   wire        datapath_result_valid_i,
    input   wire        datapath_result_ready_i,
    input   wire [OUT_ADDR_WIDTH-1:0] datapath_result_addr_i,

    // output addr
    output  reg [INPUT_ADDR_WIDTH-1:0]      input_addr_o    ,
    output  reg [WEIGHT_ADDR_WIDTH-1:0]     weight_addr_o   ,
    output  reg [BIAS_ADDR_WIDTH-1:0]       bias_addr_o     ,
    output  reg [OUT_ADDR_WIDTH-1:0]        output_addr_o   ,

    // output ctrl signal
    output  reg         busy_o          ,   // High while the convolution sequence is active
    output  reg         done_o          ,   // High when the convolution sequence is complete
    output  reg         output_we_o     ,   // High for one cycle when writing an output element
    output  reg         mac_en_o        ,   // Enables one MAC operation in the datapath
    output  reg         mac_last_o      ,   // Marks the final MAC for the current output element
    output  reg         acc_load_bias_o ,   // Requests bias load into the accumulator
    output  wire        input_window_req_o,

    output  wire [31:0] oc_counter_o    ,
    output  wire [31:0] oh_counter_o    ,
    output  wire [31:0] ow_counter_o    ,
    output  wire [31:0] ic_counter_o
);
    // Local parameter setup
    // Loop counter width calculation
    localparam  IC_WIDTH        = (IC       <= 1) ? 1 : $clog2(IC)      ;
    localparam  OC_WIDTH        = (OC       <= 1) ? 1 : $clog2(OC)      ;
    localparam  OUT_H_WIDTH     = (OUT_H    <= 1) ? 1 : $clog2(OUT_H)   ;
    localparam  OUT_W_WIDTH     = (OUT_W    <= 1) ? 1 : $clog2(OUT_W)   ;
    localparam  K_H_WIDTH       = (K_H      <= 1) ? 1 : $clog2(K_H)     ;
    localparam  K_W_WIDTH       = (K_W      <= 1) ? 1 : $clog2(K_W)     ;

    // local register
    reg [OC_WIDTH-1:0]      oc_counter_r    ;
    reg [OUT_H_WIDTH-1:0]   oh_counter_r    ;
    reg [OUT_W_WIDTH-1:0]   ow_counter_r    ;

    reg [IC_WIDTH-1:0]      ic_counter_r    ;
    reg [K_H_WIDTH-1:0]     kh_counter_r    ;
    reg [K_W_WIDTH-1:0]     kw_counter_r    ;

    // local wire
    wire    last_mac_op_w       ;
    wire    last_scalar_mac_op_w;
    wire    last_kernel_mac_op_w;
    wire    last_output_op_w    ;

    // assign
    assign  last_scalar_mac_op_w = (ic_counter_r == IC     - 1) &&
                                   (kh_counter_r == K_H    - 1) &&
                                   (kw_counter_r == K_W    - 1) ;

    assign  last_kernel_mac_op_w = (ic_counter_r == IC     - 1) ;

    assign  last_mac_op_w        = PARALLEL_KERNEL ? last_kernel_mac_op_w
                                                   : last_scalar_mac_op_w ;

    assign  last_output_op_w =  (oc_counter_r == OC     - 1) &&
                                (oh_counter_r == OUT_H  - 1) &&
                                (ow_counter_r == OUT_W  - 1) ;

    assign  oc_counter_o = oc_counter_r ;
    assign  oh_counter_o = oh_counter_r ;
    assign  ow_counter_o = ow_counter_r ;
    assign  ic_counter_o = ic_counter_r ;

    // Flat Addr Operation
    wire    [INPUT_ADDR_WIDTH-1:0]   ih_w                               ;
    wire    [INPUT_ADDR_WIDTH-1:0]   iw_w                               ;

    assign  ih_w    = oh_counter_r * STRIDE + kh_counter_r - PADDING    ;
    assign  iw_w    = ow_counter_r * STRIDE + kw_counter_r - PADDING    ;

    // FSM State
    // IDLE -> LOAD_BIAS_ADDR -> LOAD_BIAS -> MAC_ADDR -> WAIT_WINDOW
    //      -> MAC_EXEC -> NEXT_OUT ...
    //      -> WRITE_OUT waits only for the final in-flight datapath result.
    reg [3:0] present_state, next_state;

    localparam  IDLE            = 4'b0000   ,   // Wait for the start signal
                LOAD_BIAS_ADDR  = 4'b0001   ,   // Provide the bias address for the current output channel
                LOAD_BIAS       = 4'b0011   ,   // Load bias into the accumulator for a new output element
                MAC_ADDR        = 4'b0010   ,   // Provide input and weight addresses
                WAIT_WINDOW     = 4'b0110   ,   // Wait until line/window buffer can serve the requested window
                MAC_EXEC        = 4'b1110   ,   // Execute one MAC operation
                WRITE_OUT       = 4'b1111   ,   // Drain the final in-flight output result
                NEXT_OUT        = 4'b0101   ,   // Move to the next output element
                DONE            = 4'b0100   ;   // Signal completion

    assign input_window_req_o = (present_state == WAIT_WINDOW);

    // fsm phase 1: next state -> present state control
    always @(posedge clk_i) begin
        if (!rst_n) begin
            present_state <= IDLE       ;
        end
        else begin
            present_state <= next_state ;
        end
    end

    // fsm phase 2: state control
    always @(*) begin
        case (present_state)
            IDLE: begin
                if (start_i) begin
                    next_state = LOAD_BIAS_ADDR ;
                end
                else begin
                    next_state = IDLE           ;
                end
            end

            LOAD_BIAS_ADDR: begin
                next_state = LOAD_BIAS          ;
            end

            LOAD_BIAS: begin
                next_state = MAC_ADDR           ;
            end

            MAC_ADDR: begin
                next_state = WAIT_WINDOW        ;
            end

            WAIT_WINDOW: begin
                if (input_window_valid_i &&
                    (!last_mac_op_w ||
                     !datapath_result_valid_i ||
                     datapath_result_ready_i)) begin
                    next_state = MAC_EXEC       ;
                end
                else begin
                    next_state = WAIT_WINDOW    ;
                end
            end

            MAC_EXEC: begin
                if (last_mac_op_w) begin
                    if (last_output_op_w) begin
                        next_state = WRITE_OUT  ;
                    end
                    else begin
                        next_state = NEXT_OUT   ;
                    end
                end
                else begin
                    next_state = MAC_ADDR       ;
                end
            end

            WRITE_OUT: begin
                if (datapath_result_valid_i && datapath_result_ready_i &&
                    (datapath_result_addr_i == output_addr_o)) begin
                    next_state = DONE           ;
                end
                else begin
                    next_state = WRITE_OUT      ;
                end
            end

            NEXT_OUT: begin
                if (last_output_op_w) begin
                    next_state = DONE           ;
                end
                else begin
                    next_state = LOAD_BIAS_ADDR ;
                end
            end

            DONE: begin
                if (!start_i) begin
                    next_state = IDLE           ;
                end
                else begin
                    next_state = DONE           ;
                end
            end

            default: begin
                next_state = IDLE               ;
            end
        endcase
    end

    // fsm phase 3: signal control
    always @(posedge clk_i) begin
        if (!rst_n) begin
            busy_o              <= 1'b0                         ;
            done_o              <= 1'b0                         ;
            output_we_o         <= 1'b0                         ;
            mac_en_o            <= 1'b0                         ;
            mac_last_o           <= 1'b0                         ;
            acc_load_bias_o     <= 1'b0                         ;

            oc_counter_r        <= {OC_WIDTH{1'b0}}             ;
            oh_counter_r        <= {OUT_H_WIDTH{1'b0}}          ;
            ow_counter_r        <= {OUT_W_WIDTH{1'b0}}          ;
            ic_counter_r        <= {IC_WIDTH{1'b0}}             ;
            kh_counter_r        <= {K_H_WIDTH{1'b0}}            ;
            kw_counter_r        <= {K_W_WIDTH{1'b0}}            ;

            input_addr_o        <= {INPUT_ADDR_WIDTH{1'b0}}     ;
            weight_addr_o       <= {WEIGHT_ADDR_WIDTH{1'b0}}    ;
            bias_addr_o         <= {BIAS_ADDR_WIDTH{1'b0}}      ;
            output_addr_o       <= {OUT_ADDR_WIDTH{1'b0}}       ;
        end
        else begin
            mac_last_o <= 1'b0;

            case (present_state)
                IDLE: begin
                    busy_o              <= 1'b0     ;
                    done_o              <= 1'b0     ;
                    output_we_o         <= 1'b0     ;
                    mac_en_o            <= 1'b0     ;
                    acc_load_bias_o     <= 1'b0     ;

                    if (start_i) begin
                        oc_counter_r    <= {OC_WIDTH{1'b0}}    ;
                        oh_counter_r    <= {OUT_H_WIDTH{1'b0}} ;
                        ow_counter_r    <= {OUT_W_WIDTH{1'b0}} ;
                        ic_counter_r    <= {IC_WIDTH{1'b0}}    ;
                        kh_counter_r    <= {K_H_WIDTH{1'b0}}   ;
                        kw_counter_r    <= {K_W_WIDTH{1'b0}}   ;
                    end
                end

                LOAD_BIAS_ADDR: begin
                    busy_o              <= 1'b1                 ;   // toggle
                    done_o              <= 1'b0                 ;
                    output_we_o         <= 1'b0                 ;
                    mac_en_o            <= 1'b0                 ;
                    acc_load_bias_o     <= 1'b0                 ;

                    bias_addr_o         <= oc_counter_r         ;
                    output_addr_o       <= oc_counter_r * OUT_H * OUT_W
                                        + oh_counter_r * OUT_W
                                        + ow_counter_r          ;

                    // initialization for 2nd ~ operation
                    ic_counter_r        <= {IC_WIDTH{1'b0}}     ;
                    kh_counter_r        <= {K_H_WIDTH{1'b0}}    ;
                    kw_counter_r        <= {K_W_WIDTH{1'b0}}    ;
                end

                LOAD_BIAS: begin
                    busy_o              <= 1'b1     ;
                    done_o              <= 1'b0     ;
                    output_we_o         <= 1'b0     ;
                    mac_en_o            <= 1'b0     ;
                    acc_load_bias_o     <= 1'b1     ;   // toggle
                end

                MAC_ADDR: begin
                    busy_o              <= 1'b1     ;
                    done_o              <= 1'b0     ;
                    output_we_o         <= 1'b0     ;
                    mac_en_o            <= 1'b0     ;
                    acc_load_bias_o     <= 1'b0     ;   // toggle

                    if (PARALLEL_KERNEL) begin
                        input_addr_o    <= ic_counter_r * IN_H * IN_W
                                        + (oh_counter_r * STRIDE - PADDING) * IN_W
                                        + (ow_counter_r * STRIDE - PADDING) ;

                        weight_addr_o   <= oc_counter_r * IC * K_H * K_W
                                        + ic_counter_r * K_H * K_W ;
                    end
                    else begin
                        input_addr_o    <= ic_counter_r * IN_H * IN_W
                                        + ih_w * IN_W
                                        + iw_w ;

                        weight_addr_o   <= oc_counter_r * IC * K_H * K_W
                                        + ic_counter_r * K_H * K_W
                                        + kh_counter_r * K_W
                                        + kw_counter_r  ;
                    end
                end

                WAIT_WINDOW: begin
                    busy_o              <= 1'b1     ;
                    done_o              <= 1'b0     ;
                    output_we_o         <= 1'b0     ;
                    mac_en_o            <= 1'b0     ;
                    acc_load_bias_o     <= 1'b0     ;
                end

                MAC_EXEC: begin
                    busy_o              <= 1'b1     ;
                    done_o              <= 1'b0     ;
                    output_we_o         <= 1'b0     ;
                    mac_en_o            <= 1'b1     ;   // toggle
                    mac_last_o          <= last_mac_op_w;
                    acc_load_bias_o     <= 1'b0     ;

                    if (!last_mac_op_w) begin
                        if (PARALLEL_KERNEL) begin
                            ic_counter_r <= ic_counter_r + 1'b1 ;
                        end
                        else begin
                            if (kw_counter_r == K_W - 1) begin
                                kw_counter_r <= {K_W_WIDTH{1'b0}}       ;

                                if (kh_counter_r == K_H - 1) begin
                                    kh_counter_r <= {K_H_WIDTH{1'b0}}   ;
                                    ic_counter_r <= ic_counter_r + 1'b1 ;
                                end
                                else begin
                                    kh_counter_r <= kh_counter_r + 1'b1 ;
                                end
                            end
                            else begin
                                kw_counter_r <= kw_counter_r + 1'b1     ;
                            end
                        end
                    end
                    else begin
                        output_addr_o   <= oc_counter_r * OUT_H * OUT_W
                                        + oh_counter_r * OUT_W
                                        + ow_counter_r  ;
                    end
                end

                WRITE_OUT: begin
                    busy_o              <= 1'b1     ;
                    done_o              <= 1'b0     ;
                    output_we_o         <= datapath_result_valid_i && datapath_result_ready_i;
                    mac_en_o            <= 1'b0     ;   // toggle
                    acc_load_bias_o     <= 1'b0     ;
                end

                NEXT_OUT: begin
                    busy_o              <= 1'b1     ;
                    done_o              <= 1'b0     ;
                    output_we_o         <= 1'b0     ;   // toggle
                    mac_en_o            <= 1'b0     ;
                    acc_load_bias_o     <= 1'b0     ;

                    if (!last_output_op_w) begin
                        if (ow_counter_r == OUT_W - 1) begin
                            ow_counter_r <= {OUT_W_WIDTH{1'b0}}     ;

                            if (oh_counter_r == OUT_H - 1) begin
                                oh_counter_r <= {OUT_H_WIDTH{1'b0}} ;
                                oc_counter_r <= oc_counter_r + 1'b1 ;
                            end
                            else begin
                                oh_counter_r <= oh_counter_r + 1'b1 ;
                            end
                        end
                        else begin
                            ow_counter_r <= ow_counter_r + 1'b1     ;
                        end
                    end
                end

                DONE: begin
                    busy_o              <= 1'b0     ;   // toggle
                    done_o              <= 1'b1     ;   // toggle
                    output_we_o         <= 1'b0     ;
                    mac_en_o            <= 1'b0     ;
                    acc_load_bias_o     <= 1'b0     ;
                end

                default: begin
                    busy_o              <= 1'b0     ;
                    done_o              <= 1'b0     ;
                    output_we_o         <= 1'b0     ;
                    mac_en_o            <= 1'b0     ;
                    acc_load_bias_o     <= 1'b0     ;
                end
            endcase
        end
    end

endmodule
