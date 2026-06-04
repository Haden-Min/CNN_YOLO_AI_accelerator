module acc #(
    parameter IN_WIDTH  = 16,
    parameter ACC_WIDTH = 32
)(
    input wire clk,
    input wire rst_n,

    input wire clear_i,
    input wire load_bias_i,
    input wire en_i,

    input wire signed [IN_WIDTH-1:0]  data_i,
    input wire signed [ACC_WIDTH-1:0] bias_i,

    output reg signed [ACC_WIDTH-1:0] acc_o
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        acc_o <= 0;
    end
    else if (clear_i) begin
        acc_o <= 0;
    end
    else if (load_bias_i) begin
        acc_o <= bias_i;
    end
    else if (en_i) begin
        acc_o <= acc_o + data_i;
    end
end

endmodule