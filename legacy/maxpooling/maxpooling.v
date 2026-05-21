module maxpooling
(
				clk			,
				reset_n		,
				in			,
				result			
);

	input				clk		;
	input				reset_n	;
	input		[31:0]	in		;

	wire		[7:0] 	in_1	;
	wire		[7:0]  	in_2	;
	wire		[7:0]  	in_3	;
	wire		[7:0]  	in_4	;

	output reg  [7:0]	result	;

	wire	    [7:0]	result_1  ;
	wire	    [7:0]	result_2  ;
	wire	    [7:0]	nxt_result;

	assign	in_1 [7:0]	=	in	[7:0]	;
	assign	in_2 [7:0]	=	in	[15:8]	;
	assign	in_3 [7:0]	=	in	[23:16]	;
	assign	in_4 [7:0]	=	in	[31:24]	;

	always @ (posedge clk) begin
		if(!reset_n)	result	<=	1'b0;
		else			result	<=	nxt_result;
	end

	assign	result_1	=	(in_1>=in_2)	?	in_1	:	in_2	;
	assign	result_2	=	(in_3>=in_4)	?	in_3	:	in_4	;
	assign	nxt_result		=	(result_1>=result_2)	?	result_1	:	result_2	;

endmodule

