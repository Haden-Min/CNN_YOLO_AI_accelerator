`timescale 1ns/1ps

module tb_tile_conv_axi_perf_28;
    tb_single_conv_tile_axi #(
        .TILE_WIDTH(28),
        .TILE_HEIGHT(28),
        .ENABLE_BACKPRESSURE(0),
        .CONTINUOUS_INPUT(1)
    ) u_test ();
endmodule

module tb_tile_conv_axi_perf_16;
    tb_single_conv_tile_axi #(
        .TILE_WIDTH(16),
        .TILE_HEIGHT(16),
        .ENABLE_BACKPRESSURE(0),
        .CONTINUOUS_INPUT(1)
    ) u_test ();
endmodule
