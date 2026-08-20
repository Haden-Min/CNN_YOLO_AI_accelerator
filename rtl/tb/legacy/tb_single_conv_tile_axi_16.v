`timescale 1ns/1ps

module tb_single_conv_tile_axi_16;
    tb_single_conv_tile_axi #(
        .TILE_WIDTH(16),
        .TILE_HEIGHT(16)
    ) u_test ();
endmodule
