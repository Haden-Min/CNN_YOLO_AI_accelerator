`timescale 1ns/1ps
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
