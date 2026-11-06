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
            // Reset followed by trace enable
            KEY[0] <= 0;    SW[0] <= 0;     @(posedge CLOCK_50);
                                repeat(500) @(posedge CLOCK_50);
            KEY[0] <= 1;                    @(posedge CLOCK_50);
                                  repeat(1) @(posedge CLOCK_50);
                            SW[0] <= 1;     @(posedge CLOCK_50);
                              repeat(10000) @(posedge CLOCK_50);
            // Trace enable followed by reset
            KEY[0] <= 0;    SW[0] <= 0;     @(posedge CLOCK_50);
                                repeat(500) @(posedge CLOCK_50);
                            SW[0] <= 1;     @(posedge CLOCK_50);
                                repeat(500) @(posedge CLOCK_50);
            KEY[0] <= 1;                    @(posedge CLOCK_50);
                              repeat(10000) @(posedge CLOCK_50);
			$stop;					
							
		end
		
		
endmodule	