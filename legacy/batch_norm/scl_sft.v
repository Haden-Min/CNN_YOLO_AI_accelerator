module scl_sft
(
	input [7:0] x,
	input [7:0] weight,
	input [7:0] bias,

	output [7:0] res
);

	assign res = weight*x + bias	;

endmodule
