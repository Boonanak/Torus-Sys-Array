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
            SW[9:6] = 4'b0000; // Clock at 50 MHz
            SW[5:1] = 5'b00001; // running benchmark 1
            // Trace enable followed by reset
            KEY[0] <= 0;    SW[0] <= 0;     @(posedge CLOCK_50);
                                repeat(500) @(posedge CLOCK_50);
                            SW[0] <= 1;     @(posedge CLOCK_50);
                              repeat(15000) @(posedge CLOCK_50);
            KEY[0] <= 1;                    @(posedge CLOCK_50);
                              repeat(15000) @(posedge CLOCK_50);
            SW[9:6] = 4'b1000; // Clock at 195 kHz
            SW[5:1] = 5'b00011; // running benchmark 2
            KEY[0] <= 0;     repeat(100000) @(posedge CLOCK_50);
            KEY[0] <= 1;     repeat(750000) @(posedge CLOCK_50);
            SW[9:6] = 4'b0100; // Clock at 3.1 MHz
            SW[5:1] = 5'b00111; // running benchmark 3
            KEY[0] <= 0;     repeat(100000) @(posedge CLOCK_50);
            KEY[0] <= 1;     repeat(250000) @(posedge CLOCK_50);
            SW[9:6] = 4'b0010; // Clock at 12.5 MHz
            SW[5:1] = 5'b01111; // running benchmark 4
            KEY[0] <= 0;      repeat(50000) @(posedge CLOCK_50);
            KEY[0] <= 1;      repeat(50000) @(posedge CLOCK_50);
            SW[9:6] = 4'b0001; // Clock at 25 MHz
            SW[5:1] = 5'b11111; // running benchmark 5
            KEY[0] <= 0;        repeat(500) @(posedge CLOCK_50);
            KEY[0] <= 1;      repeat(50000) @(posedge CLOCK_50);
            SW[9:6] = 4'b0000; // Clock at 50 MHz
            SW[5:1] = 5'b10001; // running benchmark 6
            KEY[0] <= 0;        repeat(500) @(posedge CLOCK_50);
            KEY[0] <= 1;      repeat(50000) @(posedge CLOCK_50);
			$stop;					
							
		end
		
		
endmodule	