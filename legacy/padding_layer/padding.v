
module padding (
                input clk,
                input reset,
                input padding_en,
                input imgDataValid,

                input [7:0] R_input,
                input [7:0] G_input,
                input [7:0] B_input,

                output reg intr,

                output reg [3343:0] R_row0, //418x8=3344
                output reg [3343:0] G_row0,
                output reg [3343:0] B_row0,
                 
                output reg [3343:0] R_row1, //418x8=3344
                output reg [3343:0] G_row1,
                output reg [3343:0] B_row1,
                
                output reg [3343:0] R_row2, //418x8=3344
                output reg [3343:0] G_row2,
                output reg [3343:0] B_row2

);

reg [3:0] present_state, next_state;
reg [2:0] ctrl;
reg [8:0] count;

localparam IDLE = 4'd0;
localparam S1   = 4'd1;
localparam S2   = 4'd2;
localparam S3   = 4'd3;
localparam S4   = 4'd4;

always @(posedge clk) begin 
    if(reset) begin
        present_state <= IDLE;
        
    end
    else begin
        present_state <= next_state;
        
    end
end

always @(*) begin
    case (present_state)
        IDLE: begin
            if (padding_en == 1 && imgDataValid == 1) begin
                next_state = S1;

            end else begin
                next_state = IDLE;
            end
        end
        S1: begin
            if (ctrl == 1 && imgDataValid == 1) begin
                next_state = S2;

            end else begin
                next_state = S1;
            end
        end
        S2: begin
            if (ctrl == 2 && imgDataValid == 1) begin
                next_state = S3;

            end else begin
                next_state = S2;
            end
        end
        S3: begin
            if (ctrl == 3 && imgDataValid == 1) begin
                next_state = S4; 
            end else begin
                next_state = S3;
            end
        end
        S4: begin
            if (ctrl == 4 && imgDataValid == 1) begin
                next_state = IDLE; 
            end 
            else begin
                next_state = S4;
            end
        end

        default: begin
            next_state = IDLE;
        end
    endcase
end

always @(posedge clk) begin // * 하면 출력 안나옴
    case(present_state)
        IDLE: begin
            R_row0 = 3343'd0;
            G_row0 = 3343'd0;
            B_row0 = 3343'd0;
            R_row1 = 3343'd0;
            G_row1 = 3343'd0;
            B_row1 = 3343'd0;
            R_row2 = 3343'd0;
            G_row2 = 3343'd0;
            B_row2 = 3343'd0;

            ctrl   = 3'd0;
            intr   = 0;
            count  = 0;
        end
        
        S1: begin
            R_row0 = {R_row0[3343:8], R_input} << 8;
            G_row0 = {G_row0[3343:8], G_input} << 8;
            B_row0 = {B_row0[3343:8], B_input} << 8;
            
            count = count+1;
            intr   = 0;

            if(count==9'd416)
                count = 0;

            if(count==9'd415) begin
                ctrl  = 3'd1;
            end

            
        end

        S2: begin
            R_row1 = {R_row1[3343:8],R_input} << 8;
            G_row1 = {G_row1[3343:8],G_input} << 8;
            B_row1 = {B_row1[3343:8],B_input} << 8;
            
            count = count+1;
            intr   = 0;
            
            if(count==9'd416)
                count = 0;
            if(count==9'd415) begin
                ctrl  = 3'd2;
            end


        end
        
        S3: begin
            R_row2 = {R_row2[3343:8],R_input} << 8;
            G_row2 = {G_row2[3343:8],G_input} << 8;
            B_row2 = {B_row2[3343:8],B_input} << 8;
            count = count+1;
            intr = 0;

            if(count==9'd416)
                count = 0;
                

            if(count==9'd415) begin
                ctrl  = 3'd3;

            end
        end

            S4: begin
                intr = 1;
                ctrl = 3'd4;
            end

    endcase
end

endmodule
