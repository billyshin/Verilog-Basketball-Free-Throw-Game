// ================================ Top module ===================================
module project
	(
		CLOCK_50,						//	On Board 50 MHz
		// Your inputs and outputs here
        KEY,
		// The ports below are for the VGA output.  Do not change.
		VGA_CLK,   						//	VGA Clock
		VGA_HS,							//	VGA H_SYNC
		VGA_VS,							//	VGA V_SYNC
		VGA_BLANK_N,					//	VGA BLANK
		VGA_SYNC_N,						//	VGA SYNC
		VGA_R,   						//	VGA Red[9:0]
		VGA_G,	 						//	VGA Green[9:0]
		VGA_B,   						//	VGA Blue[9:0]
		// Hex dispaly
		HEX0,
		HEX3,
		SW[2:0],
		LEDR[9:0]
	);

	input				CLOCK_50;		//	50 MHz
	input		[3:0]	KEY;           // KEY[0] Start 
	input		[2:0] SW;

	// Declare your inputs and outputs here
	// Do not change the following outputs
	output			VGA_CLK;   		//	VGA Clock      
	output			VGA_HS;			//	VGA H_SYNC
	output			VGA_VS;			//	VGA V_SYNC
	output			VGA_BLANK_N;	//	VGA BLANK
	output			VGA_SYNC_N;		//	VGA SYNC
	output	[9:0]	VGA_R;   		//	VGA Red[9:0]
	output	[9:0]	VGA_G;	 		//	VGA Green[9:0]	
	output	[9:0]	VGA_B;   		//	VGA Blue[9:0]
	output 	[6:0] HEX0;
	output 	[6:0]	HEX3;
	output	[9:0] LEDR;
	
	// reset_n
	wire 				resetn;
	assign resetn = KEY[0];
	
	// Create the colour, x, y and writeEn wires that are inputs to the controller.
	wire 		[2:0] 	colour;
	wire 		[7:0] 	x;
	wire 		[6:0]		y;
	wire 					writeEn;
	wire 					ld_ball, ld_basket, move_ball, move_basket, draw_clk, second, second_round, ld_newball;
	wire		[14:0]	address;
	wire 		[3:0] 	score, remain;
	wire 		[19:0] 	rate_count;
	wire 		[4:0] 	current_state;

	// Create an Instance of a VGA controller - there can be only one!
	// Define the number of colours as well as the initial background
	// image file (.MIF) for the controller.
	vga_adapter VGA(
			.resetn(resetn),
			.clock(CLOCK_50),
			.colour(colour),
			.x(x),
			.y(y),
			.plot(writeEn),
			/* Signals for the DAC to drive the monitor. */
			.VGA_R(VGA_R),
			.VGA_G(VGA_G),
			.VGA_B(VGA_B),
			.VGA_HS(VGA_HS),
			.VGA_VS(VGA_VS),
			.VGA_BLANK(VGA_BLANK_N),
			.VGA_SYNC(VGA_SYNC_N),
			.VGA_CLK(VGA_CLK));
		defparam VGA.RESOLUTION = "160x120";
		defparam VGA.MONOCHROME = "FALSE";
		
		
		defparam VGA.BITS_PER_COLOUR_CHANNEL = 1;
		defparam VGA.BACKGROUND_IMAGE = "black.mif";
			
	// Put your code here. Your code should produce signals x,y,colour and writeEn/plot
	// for the VGA controller, in addition to any other functionality your design may require.
    
	// Instansiate datapath
	// datapath(rate_count, clock, reset_n, reset, enable, ld_ball, ld_newball, ld_basket, move_ball, move_basket, draw_clk, second, load_remain, color_out, address, score, second_round);
	datapath(SW[2:0], rate_count, CLOCK_50, resetn, reset, writeEn, ld_ball, ld_newball, ld_basket, move_ball, move_basket, draw_clk, second, load_remain, colour, address, score, second_round);
	
   // Instansiate FSM control
	// Input: KEY[0] = reset_n
	//        KEY[1] = start
	//        KEY[2] = load ball
	//        KEY[3] = throw ball
	// control(draw_clk, reset_n, start, load, throw, second_round, ld_ball, ld_newball, ld_basket, move_ball, move_basket, writeEn, second, current_state, load_remain);
	control c0(draw_clk, resetn, ~KEY[1], ~KEY[2], ~KEY[3], second_round, ld_ball, ld_newball, ld_basket, move_ball, move_basket, writeEn, second, current_state, remain);
	
	// count every 1 frame
	delay_counter d0(CLOCK_50, resetn, 1'b1, rate_count);
	assign draw_clk = (rate_count == 20'b0000_0000_0000_0000_0000) ? 1'b1 : 1'b0;
	
	// Display score
	hex_decoder h0(score, HEX3);
    
	// Display number of remaining balls	
	//remaining_ball r0(resetn, load_remain, ~KEY[3], remain);
	hex_decoder h1(remain, HEX0);
    
	// x coordinate
	assign x = address[7:0];
	
	// y coordinate
	assign y = address[14:8];
	
	assign LEDR[4:0] = current_state;
endmodule

// =========================================================================== datapath ========================================================================================
module datapath(data_in, rate_count, clock, reset_n, reset, enable, ld_ball, ld_newball, ld_basket, move_ball, move_basket, draw_clk, second, load_remain, color_out, address, score, second_round);
	input 				    clock, reset_n, reset, enable, ld_ball, ld_newball, ld_basket, move_ball, move_basket, draw_clk, second, load_remain;
	input 		[19:0] 	rate_count;
	input 		[2:0]		data_in;
	output		[14:0]	address;
	output reg	[2:0] 	color_out;
	output	   [3:0]		score;
   output               second_round;
	
	reg 			[18:0] 	address_x;
	reg 			[18:0]   address_y;
	reg 			[18:0] 	count;
	reg                  ld_score;
	
	wire 			[7:0]	   basket_x;
	wire 			[6:0]		ball_y;
	wire 						ball_frame_enable, basket_frame_enable, ball_direction;
	wire 			[2:0]		ball_frame_count;
	wire 			[2:0]		basket_frame_count;
	wire 			[2:0] 	basket_frame_counter_input;
	
	// counter for counting the whole pixel of the screen
	// we will draw the whole screen every 1 frame
	always @(posedge clock) 
	begin
	    if(!reset_n)
				count <= 19'b100_1010_1111_1111;
		else if(enable ==1'b1)
		begin
			if (draw_clk)
				count <= 19'b100_1010_1111_1111;
			if (count != 19'b000_0000_0000_0000) 
			begin
				address_x <= count % 19'b000_0000_1010_0000; // 160
				address_y <= count / 19'b000_0000_1010_0000;
				count <= count - 1'b1;
			end
		end
	end
	
	always @(*)
	begin
		color_out = 3'b000;
		// basket and board
		if (ld_basket == 1'b1)
		begin
			// Outer board 
			if ((address_x[7:0] >= basket_x) && (address_x[7:0] <= basket_x + 8'b00011110) && (address_y[6:0] >= 7'b0000101) && (address_y[6:0] <= 7'b0000101 + 7'b0011000))
				color_out = 3'b111;	// white
			// inner board
			if ((address_x[7:0] >= basket_x + 8'b00001000) && (address_x[7:0] <= basket_x + 8'b00001000 + 8'b0001100) && (address_y[6:0] >= 7'b0000111 + 7'b0001001) && (address_y[6:0] <= 7'b0000111 + 7'b0001001 + 7'b001010))
				color_out = 3'b000;	// black
			// basket
			if ((address_x[7:0] >= basket_x + 8'b00000111) && (address_x[7:0] <= basket_x + 8'b00000111 + 8'b00001110) && (address_y[6:0] >= 7'b0000110 + 7'b0010101) && (address_y[6:0] <= 7'b0000110 + 7'b0010101 + 7'b0000010))
				color_out = 3'b100;	//red
		end
		// ball
		if (ld_ball == 1'b1)
		begin
			if ((address_x[7:0] >= 8'b01001011) && (address_x[7:0] <= 8'b01001011 + 8'b00000111) && (address_y[6:0] >= ball_y) && (address_y[6:0] <= ball_y + 7'b0000111))
				begin
					if (ball_y == 8'b01101001)
					   color_out = 3'b000; // remove ball if it reaches this position
					else
				      color_out = 3'b100;	//red
				end
		end
	end
	
	// ball
	ball_y_counter b1(clock, reset_n, ball_frame_enable, ld_newball, move_ball, ball_direction, ball_y);
	// fixed speed
	// ball_frame_counter b3(clock, reset_n, draw_clk, ball_frame_count);
	// varing speed
	ball_speed_counter b3(data_in, clock, reset_n, draw_clk, ball_frame_count);
	assign ball_frame_enable = (ball_frame_count == 3'b000 && rate_count == 20'b00000000000000000001) ? 1'b1 : 1'b0;
	
	// basket
	basket_x_counter ba1(clock, reset_n, basket_frame_enable, move_basket, basket_x);
	basket_frame_counter ba2(basket_frame_counter_input, clock, reset_n, draw_clk, basket_frame_count);
	assign basket_frame_enable =  (basket_frame_count == 3'b000 && rate_count == 20'b00000000000000000001) ? 1'b1 : 1'b0;
	
	mux2to1 m0(3'b111, 3'b100, second, basket_frame_counter_input);
	
	// count score
	always @(*)
	begin
		if (!reset_n) 
			ld_score = 1'b0;
		else
		begin
			//if (second == 1'b0)
			//begin
				//if ((basket_x + 8'b00000111 > 8'b01000001) && (basket_x + 8'b00000111 < 8'b01010000) && (ball_y < 7'b0000110 + 7'b0010101 - 7'b0000101) && (ball_y > 7'b0000110 + 7'b0010101) && (ball_direction == 1'b0))
				if ((basket_x + 8'b00000111 > 8'b01000001) && (basket_x + 8'b00000111 < 8'b01010000) && (ball_direction == 1'b0) && (ball_y > 7'b0000110 + 7'b0010101 - 7'b0000010) && (ball_y < 7'b0000110 + 7'b0010101))
					ld_score = 1'b1;
				else 
					ld_score = 1'b0;
			//end
			//else if (second == 1'b1)
			//begin
			//	if ((basket_x + 8'b00000111 > 8'b01000001) && (basket_x + 8'b00000111 < 8'b01010000) && (ball_y < 7'b0000110 + 7'b0010101 - 7'b0000101) && (ball_y > 7'b0000110 + 7'b0010101) && (ball_direction == 1'b0))
			//		ld_score = 1'b1;
			//	else 
			//		ld_score = 1'b0;
			//end
		end
	end
	
	// score
	 score_counter s1 (reset_n, ld_score, score);
	 
    // signal for  second round
    assign second_round = (score > 4'b0001) ? 1'b1 : 1'b0;
	
	// output x and y coordinate
	assign address = {address_y[6:0], address_x[7:0]};
endmodule

// =========================================================================== control ========================================================================================
module control(draw_clk, reset_n, start, load, throw, second_round, ld_ball, ld_newball, ld_basket, move_ball, move_basket, writeEn, second, current_state, remain);
	input 					draw_clk, reset_n, start, throw, second_round, load;
	output reg 				ld_ball, ld_basket, move_ball, move_basket, writeEn, second, ld_newball;
	output reg	[4:0]		current_state;
	output reg	[3:0]		remain;
	wire			[19:0]	rate_count;
	wire 			[2:0] 	temp_color, color_out;
	reg 			[4:0] 	next_state;
		
	localparam S_START			   = 5'd0,
				  S_START_WAIT			= 5'd1,
				  S_DRAW			      = 5'd2,
				  S_DRAW_WAIT			= 5'd3,
				  S_BASKET_MOVE		= 5'd4,
				  S_BASKET_MOVE_WAIT	= 5'd5,
				  S_BALL_MOVE_1		= 5'd6,
				  S_BALL_LOAD_1	   = 5'd7,
				  S_BALL_MOVE_2      = 5'd8,
				  S_BALL_LOAD_2      = 5'd9,
				  S_BALL_MOVE_3      = 5'd10,
				  S_BALL_LOAD_3      = 5'd11,
				  S_BALL_MOVE_4		= 5'd12,
				  S_BALL_LOAD_4		= 5'd13,
				  S_BALL_MOVE_5 		= 5'd14,
				  S_2nd_ROUND_LOAD	= 5'd15,
				  S_2nd_ROUND_WAIT	= 5'd16,
				  S_2nd_BALL_LOAD_1	= 5'd17,
              S_2nd_BALL_MOVE_1  = 5'd18,
				  S_2nd_BALL_LOAD_2  = 5'd19,
				  S_2nd_BALL_MOVE_2  = 5'd20,
				  S_2nd_BALL_LOAD_3	= 5'd21,
				  S_2nd_BALL_MOVE_3	= 5'd22,
				  S_2nd_BALL_LOAD_4	= 5'd23,
				  S_2nd_BALL_MOVE_4  = 5'd24,
				  S_2nd_BALL_LOAD_5	= 5'd25,
				  S_2nd_BALL_MOVE_5 	= 5'd26,
				  S_END					= 5'd27;
				  
	always @(*)
	begin: state_table
				case (current_state)
					S_START: 				next_state = start 						? S_START_WAIT      : S_START;
					S_START_WAIT:			next_state = start 						? S_START_WAIT      : S_DRAW;
					S_DRAW: 					next_state = start 						? S_DRAW_WAIT       : S_DRAW;
					S_DRAW_WAIT: 			next_state = start 						? S_DRAW_WAIT       : S_BASKET_MOVE;
					S_BASKET_MOVE: 		next_state = throw 						? S_BASKET_MOVE_WAIT: S_BASKET_MOVE;
					S_BASKET_MOVE_WAIT:	next_state = throw         			? S_BASKET_MOVE_WAIT: S_BALL_MOVE_1;
					S_BALL_MOVE_1: 	   next_state = load          			? S_BALL_LOAD_1     : S_BALL_MOVE_1;
					S_BALL_LOAD_1:      	next_state = throw         			? S_BALL_MOVE_2     : S_BALL_LOAD_1;
					S_BALL_MOVE_2:	    	next_state = load          			? S_BALL_LOAD_2     : S_BALL_MOVE_2;
					S_BALL_LOAD_2: 	   next_state = throw         			? S_BALL_MOVE_3     : S_BALL_LOAD_2;
					S_BALL_MOVE_3: 	   next_state = load          			? S_BALL_LOAD_3     : S_BALL_MOVE_3;
					S_BALL_LOAD_3: 	   next_state = throw         			? S_BALL_MOVE_4 	  : S_BALL_LOAD_3;
					S_BALL_MOVE_4:      	next_state = load          			? S_BALL_LOAD_4 	  : S_BALL_MOVE_4;
					S_BALL_LOAD_4: 	   next_state = throw         			? S_BALL_MOVE_5 	  : S_BALL_LOAD_4;
					S_BALL_MOVE_5: 	   next_state = load							? S_2nd_ROUND_LOAD  : S_BALL_MOVE_5;
					S_2nd_ROUND_LOAD:		next_state = second_round				? S_2nd_ROUND_WAIT  : S_END;
					S_2nd_ROUND_WAIT:		next_state = load							? S_2nd_BALL_LOAD_1 : S_2nd_ROUND_WAIT;
					S_2nd_BALL_LOAD_1:  	next_state = throw         			? S_2nd_BALL_MOVE_1 : S_2nd_BALL_LOAD_1;
               S_2nd_BALL_MOVE_1:  	next_state = load          			? S_2nd_BALL_LOAD_2 : S_2nd_BALL_MOVE_1;
					S_2nd_BALL_LOAD_2:  	next_state = throw         			? S_2nd_BALL_MOVE_2 : S_2nd_BALL_LOAD_2;
					S_2nd_BALL_MOVE_2:  	next_state = load          			? S_2nd_BALL_LOAD_3 : S_2nd_BALL_MOVE_2;
					S_2nd_BALL_LOAD_3:  	next_state = throw         			? S_2nd_BALL_MOVE_3 : S_2nd_BALL_LOAD_3;
					S_2nd_BALL_MOVE_3:  	next_state = load          			? S_2nd_BALL_LOAD_4 : S_2nd_BALL_MOVE_3;
					S_2nd_BALL_LOAD_4:  	next_state = throw         			? S_2nd_BALL_MOVE_4 : S_2nd_BALL_LOAD_4;
					S_2nd_BALL_MOVE_4:  	next_state = load          			? S_2nd_BALL_LOAD_5 : S_2nd_BALL_MOVE_4;
					S_2nd_BALL_LOAD_5:  	next_state = throw         			? S_2nd_BALL_MOVE_5 : S_2nd_BALL_LOAD_5;
					S_2nd_BALL_MOVE_5:  	next_state = load         				? S_END             : S_2nd_BALL_MOVE_5;
					S_END:					next_state = start						? S_START			  : S_END;
				default: next_state = S_START;
				endcase
	end
	
	always @(*)
	begin: enable_signals
		ld_ball 	= 1'b0;
		move_ball = 1'b0;
		ld_basket= 1'b0;
		move_basket = 1'b0;
		writeEn 	= 1'b0;
		second = 1'b0;
		ld_newball = 1'b0;
		remain = 3'b101;
		
		case (current_state)
			S_START: begin
				writeEn = 1'b0;
				remain = 3'b101;
			end
			S_START_WAIT: begin
				writeEn = 1'b0;
				remain = 3'b101;
			end
			S_DRAW: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				writeEn = 1'b1;
				remain = 3'b101;
			end
			S_DRAW_WAIT: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				writeEn = 1'b1;
				remain = 3'b101;
			end
			S_BASKET_MOVE: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				writeEn = 1'b1;
				remain = 3'b101;
			end
			S_BASKET_MOVE_WAIT: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				writeEn = 1'b1;
				remain = 3'b101;
			end
			S_BALL_MOVE_1: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				move_ball = 1'b1;
				writeEn = 1'b1;
				remain = 3'b100;
			end
			S_BALL_LOAD_1: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				writeEn = 1'b1;
				ld_newball = 1'b1;
				remain = 3'b100;
			end
			S_BALL_MOVE_2: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				move_ball = 1'b1;
				writeEn = 1'b1;
				remain = 3'b011;
			end
			S_BALL_LOAD_2: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				writeEn = 1'b1;
				ld_newball = 1'b1;
				remain = 3'b011;
			end
			S_BALL_MOVE_3: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				move_ball = 1'b1;
				writeEn = 1'b1;
				remain = 3'b010;
			end
			S_BALL_LOAD_3: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				writeEn = 1'b1;
				ld_newball = 1'b1;
				remain = 3'b010;
			end
			S_BALL_MOVE_4: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				move_ball = 1'b1;
				writeEn = 1'b1;
				remain = 3'b001;
			end
			S_BALL_LOAD_4: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				writeEn = 1'b1;
				ld_newball = 1'b1;
				remain = 3'b001;
			end
			S_BALL_MOVE_5: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				move_ball = 1'b1;
				writeEn = 1'b1;
				remain = 3'b000;
			end
			S_2nd_ROUND_WAIT: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				writeEn = 1'b1;
				remain = 3'b000;
			end
			S_2nd_ROUND_WAIT: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				writeEn = 1'b1;
				remain = 3'b000;
			end
			S_2nd_BALL_LOAD_1: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				writeEn = 1'b1;
				second = 1'b1;
				ld_newball = 1'b1;
				remain = 3'b101;
			end
            S_2nd_BALL_MOVE_1: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				move_ball = 1'b1;
				writeEn = 1'b1;
				second = 1'b1;
				remain = 3'b100;
			end
			S_2nd_BALL_LOAD_2: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				writeEn = 1'b1;
				second = 1'b1;
				ld_newball = 1'b1;
				remain = 3'b100;
			end
			S_2nd_BALL_MOVE_2: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				move_ball = 1'b1;
				writeEn = 1'b1;
				second = 1'b1;
				remain = 3'b011;
			end
			S_2nd_BALL_LOAD_3: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				writeEn = 1'b1;
				second = 1'b1;
				ld_newball = 1'b1;
				remain = 3'b011;
			end
			S_2nd_BALL_MOVE_3: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				move_ball = 1'b1;
				writeEn = 1'b1;
				second = 1'b1;
				remain = 3'b010;
			end
			S_2nd_BALL_LOAD_4: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				writeEn = 1'b1;
				second = 1'b1;
				ld_newball = 1'b1;
				remain = 3'b010;
			end
			S_2nd_BALL_MOVE_4: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				move_ball = 1'b1;
				writeEn = 1'b1;
				second = 1'b1;
				remain = 3'b001;
			end
			S_2nd_BALL_LOAD_5: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				writeEn = 1'b1;
				second = 1'b1;
				ld_newball = 1'b1;
				remain = 3'b001;
			end
			S_2nd_BALL_MOVE_5: begin
				ld_ball = 1'b1;
				ld_basket = 1'b1;
				move_basket = 1'b1;
				move_ball = 1'b1;
				writeEn = 1'b1;
				second = 1'b1;
				remain = 3'b000;
			end
			S_END: begin
				ld_basket = 1'b1;
				writeEn = 1'b1;
				second = 1'b1;
				remain = 3'b000;
			end
		endcase
	end
	
	always @(posedge draw_clk)
	begin: state_FFs
		if (reset_n == 1'b0)
			current_state <= S_START;
		else 
			current_state <= next_state;
	end
endmodule

// ============================================ delay counter for frame counter ==================================================
// 50MHz => 60Hz
module delay_counter(clock,reset_n,enable,q);
		input clock;
		input reset_n;
		input enable;
		output reg [19:0] q;
		
		always @(posedge clock)
		begin
			if(reset_n == 1'b0)
				q <= 20'b11001110111001100001; 
			else if(enable ==1'b1)
			begin
			   if ( q == 20'd0 )
					q <= 20'b11001110111001100001;
				else
					q <= q - 1'b1;
			end
		end
endmodule

// ======================================================= ball ==================================================================
// counter for y coordinate of the top left corner of the ball
module ball_y_counter(clock, reset_n, enable, load, move_ball, direction, ball_y_count);
	input 					clock,enable,reset_n, load, move_ball;
	output reg	[7:0]		ball_y_count;
	output reg				direction;

	always@(posedge clock)
	begin
		if(reset_n == 1'b0 || load == 1'b1)
		begin
			ball_y_count <= 8'b01100100; // 8'b01100100 = 100 => inital position of the ball
			direction <= 1'b1; // direction == 1'b1 => moving up
		end
	   else if (enable == 1'b1 && move_ball == 1'b1)
		begin
			if (ball_y_count == 8'b01101001 && direction == 1'b0) //  8'b01101001 = 105
				ball_y_count <=  8'b01101001; // ball disappears at this position
			else 
			begin
				if(direction == 1'b1 && ball_y_count > 8'b00000000)
					ball_y_count <= ball_y_count - 8'b00000001;
				else if (direction == 1'b1 && ball_y_count == 8'b00000000)
				begin
					direction <= 1'b0; // direction == 1'b0 => moving down
					ball_y_count <= ball_y_count + 8'b00000001;
				end
				else if (direction == 1'b0 && ball_y_count < 8'b01101001)
					ball_y_count <= ball_y_count + 8'b00000001;
		   end
		end
	end
endmodule

// counter for changing the speed of the ball
// data_in == 1'b001 => move 1 pixel every 2 frames
// data_in == 1'b010 => move 1 pixel every 3 frames
// data_in == 1'b100 => move 1 pixel every 5 frames
module ball_speed_counter(data_in, clock, reset_n, enable, q);
	input				[2:0]	data_in;
	input 					clock,reset_n,enable;
	output	reg	[2:0]	q;
	
	always @(posedge clock)
	begin
		if(reset_n == 1'b0)
			q <= data_in;
		else if(enable == 1'b1)
		begin
		  if(q == 3'b000)
			  q <= data_in;
		  else
			  q <= q - 3'b001;
		end
   end
endmodule

// ================================================== basket ========================================================
// counter for x coordinate of the top left corner of the baseket
module basket_x_counter(clock, reset_n, enable, move_basket, basket_x_count);
	input 				clock, enable, reset_n, move_basket;
	output reg	[7:0]	basket_x_count;
	reg					direction;
	
	always@(posedge clock)
	begin
		if(reset_n == 1'b0)
		begin
			basket_x_count <= 8'b00000000;
			direction <= 1'b1; // direction == 1'b1 => moving right
		end
	   else if (enable == 1'b1 && move_basket == 1'b1)
			begin
			if(direction == 1'b1 && basket_x_count < 8'b10000001) //8'bb10000001 == 129 (right edge of the screen)
				basket_x_count <= basket_x_count + 8'b00000001;
			else if (direction == 1'b1 && basket_x_count == 8'b10000001) // if the basket reaches the right edge, then it moves left
			begin
			   direction <= 1'b0; // direction == 1'b0 => moving left
				basket_x_count <= basket_x_count - 8'b00000001;
			end
			else if (direction == 1'b0 && basket_x_count > 8'b00000000) //8'b00000000 (left edge of the screen)
				basket_x_count <= basket_x_count - 8'b00000001; 
			else if (direction == 1'b0 && basket_x_count == 8'b00000000) // if the basket reaches the left edge, then it moves right
			begin
			   direction <= 1'b1;
				basket_x_count <= basket_x_count + 8'b00000001;
			end
		   end
	end
endmodule

// frame counter for moving basket which is used to determine the speed of the basket (move 1 pixel every frames)
module basket_frame_counter(in, clock,reset_n,enable,q);
	input	 		[2:0] in;
	input 				clock,reset_n,enable;
	output reg	[2:0]	q;
	
	always @(posedge clock)
	begin
		if(reset_n == 1'b0)
			q <= in;
		else if(enable == 1'b1)
		begin
		  if(q == 3'b000)
			  q <= in;
		  else
			  q <= q - 3'b001;
		end
   end
endmodule

// =============================================== HEX display ======================================================
// HEX Display which is used to dispaly the number of remaining balls and the current score.
module hex_decoder(hex_digit, segments);
    input		[3:0] hex_digit;
    output reg	[6:0] segments;
   
    always @(*)
        case (hex_digit)
            4'h0: segments = 7'b100_0000;
            4'h1: segments = 7'b111_1001;
            4'h2: segments = 7'b010_0100;
            4'h3: segments = 7'b011_0000;
            4'h4: segments = 7'b001_1001;
            4'h5: segments = 7'b001_0010;
            4'h6: segments = 7'b000_0010;
            4'h7: segments = 7'b111_1000;
            4'h8: segments = 7'b000_0000;
            4'h9: segments = 7'b001_1000;
            4'hA: segments = 7'b000_1000;
            4'hB: segments = 7'b000_0011;
            4'hC: segments = 7'b100_0110;
            4'hD: segments = 7'b010_0001;
            4'hE: segments = 7'b000_0110;
				4'hF: segments = 7'b000_1110;   
            default: segments = 7'h7f;
        endcase
endmodule

module mux2to1(x, y, s, m);
    input	x; //selected when s is 0
    input	y; //selected when s is 1
    input	s; //select signal
    output 	m; //output
  
    assign m = s ? y : x;
endmodule

// ========================================= remaining ball =================================================
// counter for showing the number of remaining ball. Each round has 5 chances.
module remaining_ball(reset_n, load_remain, ld_ball, remain);
	input 				reset_n, load_remain, ld_ball;
	output reg	[3:0] remain;
	
	always @(posedge ld_ball or negedge reset_n)
	begin
		if (!reset_n)
			remain = 4'b0101;
		else if (load_remain == 1'b1)
			remain = 4'b0101;
		else 
		begin
			if (load_remain == 1'b0)
				remain = remain - 4'b0001;
		end
	end
endmodule

// ============================================ score =======================================================
// counter for recording the score
module score_counter(reset_n, ld_score, score);
	input 				reset_n, ld_score;
	output reg	[3:0]	score;
	
	always @(posedge ld_score or negedge reset_n)
	begin
		if (!reset_n)
			score <= 4'b0000;
		else 
			score <= score + 4'b0001;
	end
endmodule
