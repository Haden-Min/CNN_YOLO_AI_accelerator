module booth_multiplier(
								M,
								Q,
								result);


input [7:0] M, Q;

output [15:0] result;

wire [16:0] temp [7:0] ;

booth_submultiplier step1(
									.in_result({8'b0, Q, 1'b0}),
									.out_result(temp[0]),
									.M(M)
									
									);


booth_submultiplier step2(
									.in_result(temp[0]),
									.out_result(temp[1]),
									.M(M)
									
									);


booth_submultiplier step3(
									.in_result(temp[1]),
									.out_result(temp[2]),
									.M(M)
									
									);

booth_submultiplier step4(
									.in_result(temp[2]),
									.out_result(temp[3]),
									.M(M)
									
									);

booth_submultiplier step5(
									.in_result(temp[3]),
									.out_result(temp[4]),
									.M(M)
									
									);

booth_submultiplier step6(
									.in_result(temp[4]),
									.out_result(temp[5]),
									.M(M)
									
									);

booth_submultiplier step7(
									.in_result(temp[5]),
									.out_result(temp[6]),
									.M(M)
									
									);

booth_submultiplier step8(
									.in_result(temp[6]),
									.out_result(temp[7]),
									.M(M)
									
									);




assign result=temp[7][16:1];


endmodule