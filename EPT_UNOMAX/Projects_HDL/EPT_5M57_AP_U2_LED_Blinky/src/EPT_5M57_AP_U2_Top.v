//#######################################################################
//#
//#	Copyright 	Earth People Technology Inc. 2018
//#
//#
//# File Name:  EPT_5M57_AP_U2_Top.v
//# Author:     Earth People Technology
//# Date:       November 12, 2018
//# Revision:   A
//#
//# Development: EPT Data Collection Project 
//# Application: Altera MAX II CPLD
//# Description: This file contains verilog code which will allow access
//#              to Active Transfer Library. 
//#               
//#              
//#
//#************************************************************************
//#
//# Revision History:	
//#			DATE		VERSION		DETAILS		
//#			11/12/18 	1			Created
//#
//#									
//#
//#######################################################################


//************************************************************************
//* Module Declaration
//************************************************************************

module EPT_5M57_AP_U2_Top (
	
	input  wire [1:0]          aa,
	input  wire [1:0]          bc_in,
	output wire [2:0]          bc_out,
	inout  wire [7:0]		   bd_inout,
	
	inout wire   [1:0]          LB_SER,       //XIOH -- J10
	input wire   [5:0]          LB_AD,        //AD   -- J9
	input wire   [7:0]          LB_IOH,       //XIOH -- J10
	output wire  [7:0]          LB_IOL,       //XIOL -- J8
	
	
	//Transceiver Control Signals
	output wire                TR_DIR_1,
	output wire                TR_OE_1,
	
	output wire                TR_DIR_2,
	output wire                TR_OE_2,

	output wire                TR_DIR_3,
	output wire                TR_OE_3,

	
	input wire                SW_USER_1,
	input wire                SW_USER_2,

	output reg  [3:0]         LED
	);

   //-----------------------------------------------
   // Parameters
   //-----------------------------------------------
   
   //LED State Machine Parameters
   parameter                   IDLE = 0,
	                           SELECT_MODE = 1,
                               LOAD_REGISTER = 2,
                               LOAD_LEDS = 3,
                               WAIT_FOR_TIMER = 6;

   parameter                   GLOBAL_RESET_COUNT = 12'h9c8;
   
   //Control Register selections for the LED Blinky
   parameter                   RANDOM_NUMBER = 4'h1;
   parameter                   SHIFT_LEFT = 4'h2;
   parameter                   SHIFT_RIGHT = 4'h3;
   parameter                   COUNT_UP = 4'h4;
   parameter                   COUNT_DOWN = 4'h5;
   parameter                   STATIC_VALUE = 6'h6;
   
   //Timer Value Low Limit
   parameter                   TIMER_LOW_LIMIT = 24'h3ff;
   
//***************************************************************************
//* Internal Signals and Registers Declarations
//***************************************************************************
	wire                       CLK_66;
	wire                       RST;

	wire [23:0]                UC_IN;
	wire [21:0]                UC_OUT;
	
	//Finite State Machine control registers
	reg 	[6:0]              state, next;

	//Trigger Signals
	wire  [7:0]                trigger_out;
	wire [7:0]                 trigger_in_byte;	
	
	//LED registers
	wire                       led_reset;
	
	//Transfer registers
	reg                        start_transfer;
	reg                        start_transfer_reg;
	reg   [7:0]                transfer_out_byte;

    //Transfer Control registers
	wire                       transfer_in_received;
	wire [7:0]                 transfer_in_byte;
	reg  [7:0]                 transfer_control_byte;
	wire   [7:0]               control_register;
	
	//Reset signals
	wire                       reset;
	reg [11:0]                 reset_counter;
	reg                        reset_signal_reg;
	
	reg [23:0]                 timer_value;	
	reg [7:0]                  seed_value;
	reg [23:0]                 led_delay_counter;
	reg [3:0]                  random_number;
	reg [3:0]                  random_num_counter;
	reg [3:0]                  led_reg;
	wire                       random_number_generated;
	reg                        start_blinky;
	reg [3:0]                  static_load_value;
	
	reg [3:0]                  shift_count_value;

`ifdef SIM
   reg [8*26:1] state_name;
`endif
	


//***************************************************************************
//* 	Signal Assignments	
//***************************************************************************
   assign            TR_DIR_1  = 1'b1; //1 = A to B; 0 = B to A
   assign            TR_OE_1  = 1'b1;

   assign            TR_DIR_2  = 1'b1; //1 = A to B; 0 = B to A
   assign            TR_OE_2  = 1'b1; 
   
   assign            TR_DIR_3  = 1'b0; //1 = A to B; 0 = B to A
   assign            TR_OE_3  = 1'b1;  

   //Clock and Reset
   assign            CLK_66 = aa[1];
   assign            RST = reset;
   assign            reset = reset_signal_reg;
   
   //Set the trigger out to zero
   assign            trigger_out = 8'h0;
   
   //Control Register Map
   assign            led_reset = control_register[2];
   
   
//**************************************************
//* 	Reset Signal	
//**************************************************
	always @(posedge CLK_66 or negedge aa[0])
	begin
	  if(!aa[0])
	  begin
			reset_signal_reg <= 1'b0;
			reset_counter <= 0;
	  end
	  else
	  begin
		if( reset_counter < GLOBAL_RESET_COUNT )
		begin
			reset_signal_reg <= 1'b0;
			reset_counter <= reset_counter + 1'b1;
		end
		else
		begin
			reset_signal_reg <= 1'b1;
		end
	  end
	end

   //-----------------------------------------------
   // Load Timer Value
   //-----------------------------------------------

  always @(posedge CLK_66 or negedge RST)
  begin
    if(!RST)
	     timer_value <= TIMER_LOW_LIMIT;
	else 
	begin
	     if(trigger_in_byte[4])
	         timer_value[15:8] <= transfer_in_byte;
	     else if(trigger_in_byte[5])
	         timer_value[23:16] <= transfer_in_byte;
	end 
  end

   //-----------------------------------------------
   // Load Static Value
   //-----------------------------------------------

  always @(posedge CLK_66 or negedge RST)
  begin
    if(!RST)
	     static_load_value <= 0;
	else 
	begin
	     if(trigger_in_byte[0])
	         static_load_value <= transfer_in_byte[3:0];
	end 
  end

   //-----------------------------------------------
   // LED Blinky start 
   //-----------------------------------------------
  always @(posedge CLK_66 or negedge RST)
  begin
    if(!RST)
         start_blinky <= 1'b0;
	else 
	begin
	    if(control_register[7:4] > 0)
            start_blinky <= 1'b1;
		else
            start_blinky <= 1'b0;		
 	end 
  end
 
   //-----------------------------------------------
   // LED Delay Timer Counter 
   //-----------------------------------------------
  always @(posedge CLK_66 or negedge RST)
  begin
    if(!RST)
	     led_delay_counter <= TIMER_LOW_LIMIT;
	else 
	begin
	     if(state[SELECT_MODE])
		 led_delay_counter <= timer_value;
		 else if(state[WAIT_FOR_TIMER])
	         led_delay_counter <= led_delay_counter - 1'd1;
	end 
  end

   //-----------------------------------------------
   // Random Number array
   //-----------------------------------------------
  always @(posedge CLK_66 or negedge RST)
  begin
     if(!RST)
	 begin
	     random_number <= 4'h0;
		 random_num_counter <= 0;
	 end
	else 
	begin
	    if(random_num_counter < 4'h4 )
	    begin
	        random_num_counter <= random_num_counter + 1'd1;
			random_number[random_num_counter] <= random_number_generated;
		end
	    else 
		begin
	        random_num_counter <= 0;
			random_number[random_num_counter] <= random_number_generated;
		end
	end
  end

   //-----------------------------------------------
   // Send status of LEDs to Host
   //-----------------------------------------------
  always @(posedge CLK_66 or negedge RST)
  begin
    if(!RST)
	begin
		start_transfer <= 1'b0;
        transfer_out_byte <= 0;
        start_transfer_reg <= 1'b0;
	end
	else 
	begin
        if((state[WAIT_FOR_TIMER] | led_reset) & !start_transfer_reg)
		begin
		   start_transfer_reg <= 1'b1;
		   start_transfer <= 1'b1;
		   if(led_reset)
                transfer_out_byte <= {8'h0};
           else
		       transfer_out_byte <= {4'h0,~LED};
		   end
        else if((state[WAIT_FOR_TIMER] | led_reset) & start_transfer_reg)
		begin
		   start_transfer_reg <= 1'b1;
		   start_transfer <= 1'b0;
		   if(led_reset)
                transfer_out_byte <= {8'h0};
           else
		       transfer_out_byte <= {4'h0,~LED};
		end
        else if((state[SELECT_MODE] | led_reset) & start_transfer_reg)
		begin
		   start_transfer_reg <= 1'b0;
		   start_transfer <= 1'b0;
           transfer_out_byte <= 0;
		end
	end
  end
   
   //-----------------------------------------------
   // Select the LED Function from the control
   // register bits 7 to 4   
   //-----------------------------------------------
  always @(posedge CLK_66 or negedge RST)
  begin
    if(!RST)
	     led_reg <= 0;
	else 
	begin
        if (state[SELECT_MODE])
	    begin
	         case(control_register[7:4])
		       RANDOM_NUMBER:
		          led_reg = random_number;
		       SHIFT_LEFT:
		          led_reg = shift_count_value;
		       SHIFT_RIGHT:
		          led_reg = shift_count_value;
		       COUNT_UP:
		          led_reg = shift_count_value;
		       COUNT_DOWN:
		          led_reg = shift_count_value;
		       STATIC_VALUE:
		          led_reg = static_load_value;
		       default:
		          led_reg = 4'h0;
		      endcase 
        end	
    end
  end
  
   //-----------------------------------------------
   // Increment the Shift/Count value from the control
   // register bits 7 to 4   
   //-----------------------------------------------
  always @(posedge CLK_66 or negedge RST)
  begin
    if(!RST)
	     shift_count_value <= 0;
	else 
	begin
	    if(trigger_in_byte[7])
		     shift_count_value <= transfer_in_byte[3:0];
		else if (state[LOAD_REGISTER])
	    begin
	         case(control_register[7:4])
		     SHIFT_LEFT:
			 begin
		        shift_count_value[0] <= led_reg[3];
		        shift_count_value[3] <= led_reg[2];
		        shift_count_value[2] <= led_reg[1];
		        shift_count_value[1] <= led_reg[0];
		     end
		     SHIFT_RIGHT:
			 begin
		        shift_count_value[0] <= led_reg[1];
		        shift_count_value[3] <= led_reg[0];
		        shift_count_value[2] <= led_reg[3];
		        shift_count_value[1] <= led_reg[2];
		     end
		     COUNT_UP:
		        shift_count_value <= led_reg + 1'd1;
		     COUNT_DOWN:
		        shift_count_value <= led_reg - 1'd1;
		     default:
	            shift_count_value <= 0;
		    endcase   
         end
	end 
  end

   //-----------------------------------------------
   // Set the LED outputs 
   //-----------------------------------------------
  always @(posedge CLK_66 or negedge RST)
  begin
    if(!RST)
	     LED <= 4'hz;
	else 
	begin
	  if(led_reset)
	     LED <= 4'hz;
	  else if(state[LOAD_LEDS])
	  begin
		if ( led_reg[0] )
			LED[0] = 1'b0;
		else 
			LED[0] = 1'bz;
		if ( led_reg[1] )
			LED[1] = 1'b0;
		else 
			LED[1] = 1'bz;
 		if ( led_reg[2] )
			LED[2] = 1'b0;
		else 
			LED[2] = 1'bz;
		if ( led_reg[3] )
			LED[3] = 1'b0;
		else 
			LED[3] = 1'bz;
	  end
	end
  end
   //-----------------------------------------------
   // State Machine: Send Pattern to LEDs 
   //-----------------------------------------------
   // Next State Logic
   always @(posedge CLK_66 or negedge RST)
     begin
	if (!RST)
	  begin
	     state <= 7'h00;
	     state[IDLE] <= 1'b1;
	  end
	else
	  state <= next;
     end

     // State Definitions
   always @ ( state or start_blinky or random_number or
		      led_reg or led_delay_counter or control_register or
			  timer_value or shift_count_value) 
     begin
	     next = 7'h00;

	if (state[IDLE])
	  begin
	     if (start_blinky)
	       next[SELECT_MODE] = 1'b1;
	     else
	       next[IDLE] = 1'b1;
	  end
	
	if (state[SELECT_MODE])
	begin
       if(control_register[7:4] == 4'h0)        
            next[IDLE] = 1'b1;
         else		 
           next[LOAD_REGISTER] = 1'b1;
	end

	if (state[LOAD_REGISTER])
	begin
        next[LOAD_LEDS] = 1'b1;
    end
		
	if (state[LOAD_LEDS])
	begin
        next[WAIT_FOR_TIMER] = 1'b1;
    end
	
	if (state[WAIT_FOR_TIMER])
		if (led_delay_counter <= timer_value)
			next[WAIT_FOR_TIMER] = 1'b1;
		else 
			next[SELECT_MODE] = 1'b1;

			
`ifdef SIM
 	   if ( state == ( 1 << IDLE ))
		   state_name = "IDLE";
	   else if ( state == ( 1 << SELECT_MODE ))
		   state_name = "SELECT_MODE";
	   else if ( state == ( 1 << LOAD_REGISTER ))
		   state_name = "LOAD_REGISTER";
	   else if ( state == ( 1 << LOAD_LEDS ))
		   state_name = "LOAD_LEDS";
	   else if ( state == ( 1 << WAIT_FOR_TIMER ))
		   state_name = "WAIT_FOR_TIMER";
`endif


	end//end of state machine

   
   //-----------------------------------------------
   // Linear Feedback Shift Register
   //-----------------------------------------------
  lfsr                         LFSR_INST
  (
   .Q                          (random_number_generated),
   .CLK                        (CLK_66),
   .RST                        (RST),
   .SEED                       (transfer_in_byte[3:0]),
   .LOAD                       (trigger_in_byte[6])
   );	
	
   //-----------------------------------------------
   // State Machine: Control Register from Transfer In 
   //-----------------------------------------------
  active_control_register      ACTIVE_CONTROL_REG_INST
  (
   .CLK                        (CLK_66),
   .RST                        (RST),
   .TRANSFER_IN_RECEIVED       (transfer_in_received),
   .TRANSFER_IN_BYTE           (transfer_in_byte),

   .CONTROL_REGISTER           (control_register)
   );
   

   //-----------------------------------------------
   // Instantiate the EPT Active Transfer Library
   //-----------------------------------------------

	active_transfer_library	   ACTIVE_TRANSFER_LIBRARY_INST
	(	
	.aa                        (aa),
	.bc_in                     (bc_in),
	.bc_out                    (bc_out),
	.bd_inout                  (bd_inout),

	.UC_IN                     (UC_IN),
	.UC_OUT                    (UC_OUT)
	
	);
	
   //-----------------------------------------------
   // Instantiate the EPT Active Modules
   //-----------------------------------------------
wire [22*2-1:0]  uc_out_m;
eptWireOR # (.N(2)) wireOR (UC_OUT, uc_out_m);
	active_trigger             ACTIVE_TRIGGER_INST
	(
	 .uc_clk                   (CLK_66),
	 .uc_reset                 (RST),
	 .uc_in                    (UC_IN),
	 .uc_out                   (uc_out_m[ 0*22 +: 22 ]),

	 .trigger_to_host          (trigger_out),
	 .trigger_to_device        (trigger_in_byte)
	
	);

	active_transfer            ACTIVE_TRANSFER_INST_1
	(
	 .uc_clk                   (CLK_66),
	 .uc_reset                 (RST),
	 .uc_in                    (UC_IN),
	 .uc_out                   (uc_out_m[ 1*22 +: 22 ]),
	
	 .start_transfer           (start_transfer),
	 .transfer_received        (transfer_in_received),
	 
	 .transfer_busy            (),
	
	 .uc_addr                  (3'h2),

	 .transfer_to_host         (transfer_out_byte),
	 .transfer_to_device       (transfer_in_byte)	
	);
	


	
endmodule
