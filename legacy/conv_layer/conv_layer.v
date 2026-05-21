module conv_layer 
(
    input   wire                         clk_i,
    input   wire                         rst_n,
    input   wire   [27 * 8 - 1:0]         in_data,
    output  wire   [16 * 8 - 1:0]        c_o   // originally 64bit
);
    wire  valid;
    wire  [16 * 8 - 1:0]  c;
    reg   [16 * 8 - 1:0]  r_c;
    assign c_o = r_c;
    
    sys_array #(       
        .K0       (72'h01_02_03_04_FF_FE_FD_FC_FB),
        .K1       (72'h01_02_03_04_FF_FE_FD_FC_FB),
        .K2       (72'h01_02_03_04_FF_FE_FD_FC_FB),
        .K3       (72'h01_02_03_04_FF_FE_FD_FC_FB),
        .K4       (72'h01_02_03_04_FF_FE_FD_FC_FB),
        .K5       (72'h01_02_03_04_FF_FE_FD_FC_FB),
        .K6       (72'h01_02_03_04_FF_FE_FD_FC_FB),
        .K7       (72'h01_02_03_04_FF_FE_FD_FC_FB),
        .K8       (72'h01_02_03_04_FF_FE_FD_FC_FB),
        .K9       (72'h01_02_03_04_FF_FE_FD_FC_FB),
        .K10      (72'h01_02_03_04_FF_FE_FD_FC_FB),
        .K11      (72'h01_02_03_04_FF_FE_FD_FC_FB),
        .K12      (72'h01_02_03_04_FF_FE_FD_FC_FB),
        .K13      (72'h01_02_03_04_FF_FE_FD_FC_FB),
        .K14      (72'h01_02_03_04_FF_FE_FD_FC_FB),
        .K15      (72'h01_02_03_04_FF_FE_FD_FC_FB)
    )
    sys_array_0 (
            .clk_i          (clk_i),
            .rst_n          (rst_n),

            .a0             (in_data),

            .c0             (c[127:120]),
            .c1             (c[119:112]),
            .c2             (c[111:104]),
            .c3             (c[103:96]),
            .c4             (c[95:88]),
            .c5             (c[87:80]),
            .c6             (c[79:72]),
            .c7             (c[71:64]),
            .c8             (c[63:56]),
            .c9             (c[55:48]),
            .c10            (c[47:40]),
            .c11            (c[39:32]),
            .c12            (c[31:24]),
            .c13            (c[23:16]),
            .c14            (c[15:8]),
            .c15            (c[7:0]),
            .valid_o        (valid)
    );
    
    always@ (posedge clk_i) begin
        if (!rst_n) begin
            r_c <= 0;
        end
        else if (valid) begin
            r_c <= c;
       end
    end

endmodule