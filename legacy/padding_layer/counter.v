module counter (
                input clk,
                input reset,
                input en,
                input p_signal,
 
                output reg [1:0] cycle,
                output reg [8:0] count
);




always @(posedge clk or posedge p_signal or posedge reset ) begin 

    if(reset)begin
        count<=0;
        cycle<=0;
    end

    else begin
        
                if(en) begin
                    if(p_signal) begin
                        count<=count+1'b1;
                        cycle<=cycle+1'b1;
                    end
                                    
                if(cycle>2'd1)
                    cycle<=0;

                if(count>9'd414)
                    count<=0;
                

                end
                
                else begin
                cycle<=0;
                end

        


		end
	end
	
endmodule
