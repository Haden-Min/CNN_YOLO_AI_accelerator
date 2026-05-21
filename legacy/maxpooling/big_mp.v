module big_mp (
      		clk,
	  		reset_n,
			in_data	,

			o_data,
			o_weight
);

    input				clk			;
	input				reset_n		;
    input wire [511:0] in_data		;

	output	   [127:0]	o_data		;

	wire		   [31:0]	max_1       ;  
	wire		   [31:0]	max_2       ; 
	wire		   [31:0]	max_3       ;   
	wire		   [31:0]	max_4       ;     
	wire		   [31:0]	max_5       ;       
	wire		   [31:0]	max_6       ;       
	wire		   [31:0]	max_7       ;       
	wire		   [31:0]	max_8       ;       
	wire		   [31:0]	max_9       ;        
	wire		   [31:0]	max_10      ;     
	wire		   [31:0]	max_11      ;      
	wire		   [31:0]	max_12      ;      
	wire		   [31:0]	max_13      ;         
	wire		   [31:0]	max_14      ;          
	wire		   [31:0]	max_15      ;        
	wire		   [31:0]	max_16      ;         

	wire		   [7:0]	o_max_1       ;  
	wire		   [7:0]	o_max_2       ; 
	wire		   [7:0]	o_max_3       ;   
	wire		   [7:0]	o_max_4       ;     
	wire		   [7:0]	o_max_5       ;       
	wire		   [7:0]	o_max_6       ;       
	wire		   [7:0]	o_max_7       ;       
	wire		   [7:0]	o_max_8       ;       
	wire		   [7:0]	o_max_9       ;        
	wire		   [7:0]	o_max_10      ;     
	wire		   [7:0]	o_max_11      ;      
	wire		   [7:0]	o_max_12      ;      
	wire		   [7:0]	o_max_13      ;         
	wire		   [7:0]	o_max_14      ;          
	wire		   [7:0]	o_max_15      ;        
	wire		   [7:0]	o_max_16      ;         

	assign max_1 = in_data [31:0];
	assign max_2 = in_data [63:32];
	assign max_3 = in_data [95:64];
	assign max_4 = in_data [127:96];
	assign max_5 = in_data [159:128];
	assign max_6 = in_data [191:160];
	assign max_7 = in_data [223:192];
	assign max_8 = in_data [255:224];
	assign max_9 = in_data [287:256];
	assign max_10 = in_data[319:288];
	assign max_11 = in_data[351:320];
	assign max_12 = in_data[383:352];
	assign max_13 = in_data[415:384];
	assign max_14 = in_data[447:416];
	assign max_15 = in_data[479:448];
	assign max_16 = in_data[511:480];

	assign o_data	=	{o_max_16,o_max_15,o_max_14,o_max_13,o_max_12,o_max_11,o_max_10,o_max_9,o_max_8,o_max_7,o_max_6,o_max_6,o_max_5,o_max_4,o_max_3,o_max_2,o_max_1}	;
	maxpooling	U1
(
	.clk		(clk),
	.reset_n	(reset_n),
	.in			(  max_1),
	.result		(o_max_1)
);
	maxpooling	U2
(
	.clk		(clk),
	.reset_n	(reset_n),
	.in			(  max_2),
	.result		(o_max_2)
);
	maxpooling	U3
(
	.clk		(clk),
	.reset_n	(reset_n),
	.in			(  max_3),
	.result		(o_max_3)
);
	maxpooling	U4
(
	.clk		(clk),
	.reset_n	(reset_n),
	.in			(  max_4),
	.result		(o_max_4)
);
	maxpooling	U5
(
	.clk		(clk),
	.reset_n	(reset_n),
	.in			(  max_5),
	.result		(o_max_5)
);
	maxpooling	U6
(
	.clk		(clk),
	.reset_n	(reset_n),
	.in			(  max_6),
	.result		(o_max_6)
);
	maxpooling	U7
(
	.clk		(clk),
	.reset_n	(reset_n),
	.in			(  max_7),
	.result		(o_max_7)
);
	maxpooling	U8
(
	.clk		(clk),
	.reset_n	(reset_n),
	.in			(  max_8),
	.result		(o_max_8)
);
	maxpooling	U9
(
	.clk		(clk),
	.reset_n	(reset_n),
	.in			(  max_9),
	.result		(o_max_9)
);
	maxpooling	U10
(
	.clk		(clk),
	.reset_n	(reset_n),
	.in			(  max_10),
	.result		(o_max_10)
);
	maxpooling	U11
(
	.clk		(clk),
	.reset_n	(reset_n),
	.in			(  max_11),
	.result		(o_max_11)
);
	maxpooling	U12
(
	.clk		(clk),
	.reset_n	(reset_n),
	.in			(  max_12),
	.result		(o_max_12)
);
	maxpooling	U13
(
	.clk		(clk),
	.reset_n	(reset_n),
	.in			(  max_13),
	.result		(o_max_13)
);
	maxpooling	U14
(
	.clk		(clk),
	.reset_n	(reset_n),
	.in			(  max_14),
	.result		(o_max_14)
);
	maxpooling	U15
(
	.clk		(clk),
	.reset_n	(reset_n),
	.in			(  max_15),
	.result		(o_max_15)
);
	maxpooling	U16
(
	.clk		(clk),
	.reset_n	(reset_n),
	.in			(  max_16),
	.result		(o_max_16)
);

endmodule

