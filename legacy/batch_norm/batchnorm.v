module batchnorm (
    input					 clk,
	input					 i_start,
	input wire signed [31:0] in_data,       // 입력값
    input wire signed [31:0] mean,    // 평균값
    input wire signed [31:0] root_var,     // 분산값
    output wire signed [31:0] result,  // 결과값
	output					  o_complete,
	output					  o_overflow
);
	parameter	EPSILON	=	32'h0000_0001;

    // 중간 결과 저장용 변수
	wire signed [31:0]	minus_mean	;
    wire signed [31:0] x_minus_mean;
    reg signed [31:0] denominator; // sqrt(var + epsilon)
	assign	minus_mean	=	{(~mean[31]),mean[30:0]}	;

	qadd	QADD
	(
	.a		(in_data),
	.b		(minus_mean),
	.c		(x_minus_mean)
	);
	
	always@(x_minus_mean or root_var) begin
		if(root_var==0) denominator	=	EPSILON	;
		else			denominator	=	root_var;
	end

	qdiv		QDIV
	(
	 .i_clk		(clk),
	 .i_start	(i_start),
	 .i_dividend(x_minus_mean),
	 .i_divisor (denominator),
	 .o_quotient_out(result),
	 .o_complete(o_complete),
	 .o_overflow(o_overflow)
	);

endmodule

