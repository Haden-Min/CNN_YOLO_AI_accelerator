module si 
#(parameter bit_width = 8 ) 
(
    input clk,
    input en,
    input [bit_width-1 : 0] in,
    output reg [bit_width-1 : 0] out
);

    always @(posedge clk) begin
        if (en) begin
            out <= in;
        end
    end

endmodule
