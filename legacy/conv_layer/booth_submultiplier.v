module booth_submultiplier (
    input signed [16:0] in_result,
    input signed [7:0] M,
    output reg signed [16:0] out_result
);

    reg signed [16:0] temp;
    reg cin;
    wire [7:0] adder_subtractor_result;

    parameter add = 0;
    parameter sub = 1;

    // eight_bit_adder_subtractor 모듈 인스턴스화
    eight_bit_adder_subtractor compute (
        .cin(cin),
        .i0(in_result[16:9]),
        .i1(M),
        .sum(adder_subtractor_result)
    );

    always @(*) begin
        
		  temp = in_result;

        case (temp[1:0])
            2'b01: begin 
							cin = add;
							temp[16:9] = adder_subtractor_result;// 01(+)
						 end
            2'b10: begin 
							cin = sub;
							temp[16:9] = adder_subtractor_result;// 10(-)
						 end
            default: ; // 기본적으로 덧셈
        endcase

        

        out_result = temp >>> 1;
    end
endmodule