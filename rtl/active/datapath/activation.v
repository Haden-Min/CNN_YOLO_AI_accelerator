`timescale 1ns/1ps

// ============================================================================
// DEPRECATED - DO NOT USE IN NEW DESIGNS
//
// This module remains only because the existing conv_datapath hierarchy and
// regression filelists still reference it.  It approximates the negative
// slope as 1/8 and is not the final YOLOv3-Tiny activation implementation.
//
// New work must use activation_requant_int8_stream after tile_psum_buffer,
// where all input-channel partial sums and the layer bias have been combined.
// Remove this file only after its conv_datapath instance and every filelist
// reference have been removed and the existing regressions pass.
// ============================================================================
/*
module activation #(
    parameter DATA_WIDTH = 32
)(
    input wire signed [DATA_WIDTH-1:0] data_i,
    output wire signed [DATA_WIDTH-1:0] data_o
);

assign data_o = data_i;

endmodule
*/


module activation #(
    parameter DATA_WIDTH = 32,
    parameter LEAKY_SHIFT = 3
)(
    input wire signed [DATA_WIDTH-1:0] data_i,
    output wire signed [DATA_WIDTH-1:0] data_o
);

assign data_o = (data_i >= 0) ? data_i : (data_i >>> LEAKY_SHIFT);

endmodule
