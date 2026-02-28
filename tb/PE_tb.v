`timescale 1ns / 1ps
import PE_pkg::*;

module PE_tb;

    parameter OPERAND_WIDTH = 8;
    parameter ACCUMULATE_WIDTH = 16;
    parameter CLK_PERIOD = 10;

    logic clk_tb;
    logic reset_tb;
    
    int8_t A_in_tb;
    int8_t B_in_tb;
    int16_t Partial_Sum_in_tb;
    int8_t A_out_tb;
    int8_t B_out_tb;
    int16_t Partial_Sum_out_tb;

    PE DUT (
         .clk_i(clk_tb)
        ,.reset(reset_tb)
        ,.A_in(A_in_tb)
        ,.B_in(B_in_tb)
        ,.Partial_Sum_in(Partial_Sum_in_tb)
        ,.A_out(A_out_tb)
        ,.B_out(B_out_tb)
        ,.Partial_Sum_out(Partial_Sum_out_tb)
    );

    // Clock Generation
    initial begin
        clk_tb = 0;
        forever #(CLK_PERIOD/2) clk_tb = ~clk_tb;
    end

    // Stimulus
    // REPLACE WITH BSG_TAG LATER, just basic and simple directed tests for now.
    initial begin

        $dumpfile("PE_tb.vcd");
        $dumpvars();
        // Initialize Inputs
        reset_tb = 1;
        A_in_tb = 0;
        B_in_tb = 0;
        Partial_Sum_in_tb = 0;

        // Release Reset
        #(CLK_PERIOD * 2);
        reset_tb = 0;
        @(posedge clk_tb);

        // Test Case 1: Simple Multiplication and Addition
        // Expected: 2 * 3 + 10 = 16
        A_in_tb = 2;
        B_in_tb = 3;
        Partial_Sum_in_tb = 10;
        
        @(posedge clk_tb);
        #1; // Wait for propagation
        $display("TC1: A_in_tb=%d, B_in_tb=%d, Partial_Sum_in_tb=%d | Partial_Sum_out_tb=%d (Expected 16)", A_in_tb.value, B_in_tb.value, Partial_Sum_in_tb.value, Partial_Sum_out_tb.value);

        // Test Case 2: Max values for 8-bit operands
        // Expected: -20 * 15 + 0 = -300
        A_in_tb = -20; 
        B_in_tb = 15;
        Partial_Sum_in_tb = 0;

        @(posedge clk_tb);
        #1;
        $display("TC2: A_in_tb=%d, B_in_tb=%d, Partial_Sum_in_tb=%d | Partial_Sum_out_tb=%d (Expected -300)", A_in_tb.value, B_in_tb.value, Partial_Sum_in_tb.value, Partial_Sum_out_tb.value);

        // Test Case 3: Accumulation chain simulation
        // Feed the previous output back into Partial_Sum_in_tb (simulating A_in_tb systolic array)
        A_in_tb = 8'd5;
        B_in_tb = 8'd5;
        Partial_Sum_in_tb = Partial_Sum_out_tb; // Use previous result (510)
        
        @(posedge clk_tb);
        #1;
        $display("TC3: A_in_tb=%d, B_in_tb=%d, Partial_Sum_in_tb=%d | Partial_Sum_out_tb=%d (Expected -275)", A_in_tb.value, B_in_tb.value, Partial_Sum_in_tb.value, Partial_Sum_out_tb.value);

        // Test Case 4: Reset during operation
        reset_tb = 1;
        @(posedge clk_tb);
        #1;
        $display("TC4: Reset Active | Partial_Sum_out_tb=%d (Expected 0)", Partial_Sum_out_tb);

        #(CLK_PERIOD * 2);
        $finish;
    end

endmodule