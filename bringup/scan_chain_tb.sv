// Creates clock, reset, and switches trace replay on
module emu_top_tb();
		
		logic CLOCK_50;
		logic [6:0] HEX0;
		logic [3:0] KEY;
		logic [9:0] LEDR, SW;
		
		emu_top dut (.CLOCK_50, .HEX0, .KEY, .LEDR, .SW);

		parameter clock_period = 100;
		initial begin
			CLOCK_50 <= 0;
			forever #(clock_period /2) CLOCK_50 <= ~CLOCK_50;
		end 
		
		initial begin
            KEY[3:0] = 4'b1111; // initialize all keys to unpressed
            SW[9:6] = 4'b0000; // Clock at 50 MHz
            SW[5:1] = 5'b00001; // running benchmark 1
            // Trace enable followed by reset
            KEY[0] <= 0;    SW[0] <= 0;     @(posedge CLOCK_50);
                                repeat(500) @(posedge CLOCK_50);
                            SW[0] <= 1;     @(posedge CLOCK_50);
                              repeat(15000) @(posedge CLOCK_50);
            KEY[0] <= 1;                    @(posedge CLOCK_50);
                              repeat(15000) @(posedge CLOCK_50);
            SW[9:6] = 4'b0001; // Clock at 25 MHz
            SW[5:1] = 5'b00011; // running benchmark 2
            KEY[0] <= 0;     repeat(15000) @(posedge CLOCK_50);
            KEY[0] <= 1;      repeat(1000) @(posedge CLOCK_50);
            KEY[2] <= 0;       // Enable key pressed
                               repeat(500) @(posedge CLOCK_50);
            KEY[2] <= 1;       repeat(500) @(posedge CLOCK_50);
            SW[9:6] <= 5'b1000; // Set nsteps to 8
            KEY[3] <= 0;       // Shift key pressed
                               repeat(500) @(posedge CLOCK_50);
            KEY[3] <= 1;      repeat(5000) @(posedge CLOCK_50);
            SW[9:6] = 4'b0100; // Clock at 3.1 MHz
            SW[5:1] = 5'b10011; // running benchmark 7
            KEY[0] <= 0;       repeat(1000) @(posedge CLOCK_50);
            KEY[0] <= 1;       repeat(1000) @(posedge CLOCK_50);
            KEY[2] <= 0;       // Enable key pressed
                               repeat(500) @(posedge CLOCK_50);
            KEY[2] <= 1;       repeat(500) @(posedge CLOCK_50);
            KEY[1] <= 0;       // Shift key pressed (full rotation)
                               repeat(500) @(posedge CLOCK_50);
            KEY[1] <= 1;       repeat(500) @(posedge CLOCK_50);
                             repeat(10000) @(posedge CLOCK_50);
			$stop;					
							
		end
		
		
endmodule	