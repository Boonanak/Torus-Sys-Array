`timescale 1ns / 1ps

module PE_tb;

    parameter OPERAND_WIDTH = 8;
    parameter ACCUMULATE_WIDTH = 16;
    parameter CLK_PERIOD = 10;

    logic clk_i;
    logic reset;
    logic [OPERAND_WIDTH - 1 : 0] A;
    logic [OPERAND_WIDTH - 1 : 0] B;
    logic [ACCUMULATE_WIDTH - 1 : 0] C_in;
    wire  [ACCUMULATE_WIDTH - 1 : 0] C_out;

    PE #(
        .OPERAND_WIDTH(OPERAND_WIDTH),
        .ACCUMULATE_WIDTH(ACCUMULATE_WIDTH)
    ) DUT (
        .clk_i(clk_i),
        .reset(reset),
        .A(A),
        .B(B),
        .C_in(C_in),
        .C_out(C_out)
    );

    // Clock Generation
    initial begin
        clk_i = 0;
        forever #(CLK_PERIOD/2) clk_i = ~clk_i;
    end

    // Stimulus
    // REPLACE WITH BSG_TAG LATER, just basic and simple directed tests for now.
    initial begin
        // Initialize Inputs
        reset = 1;
        A = 0;
        B = 0;
        C_in = 0;

        // Release Reset
        #(CLK_PERIOD * 2);
        reset = 0;
        @(posedge clk_i);

        // Test Case 1: Simple Multiplication and Addition
        // Expected: 2 * 3 + 10 = 16
        A = 8'd2;
        B = 8'd3;
        C_in = 16'd10;
        
        @(posedge clk_i);
        #1; // Wait for propagation
        $display("TC1: A=%d, B=%d, C_in=%d | C_out=%d (Expected 16)", A, B, C_in, C_out);

        // Test Case 2: Max values for 8-bit operands
        // Expected: 255 * 2 + 0 = 510
        A = 8'hFF; 
        B = 8'd2;
        C_in = 16'd0;

        @(posedge clk_i);
        #1;
        $display("TC2: A=%d, B=%d, C_in=%d | C_out=%d (Expected 510)", A, B, C_in, C_out);

        // Test Case 3: Accumulation chain simulation
        // Feed the previous output back into C_in (simulating a systolic array)
        A = 8'd5;
        B = 8'd5;
        C_in = C_out; // Use previous result (510)
        
        @(posedge clk_i);
        #1;
        $display("TC3: A=%d, B=%d, C_in=%d | C_out=%d (Expected 535)", A, B, C_in, C_out);

        // Test Case 4: Reset during operation
        reset = 1;
        @(posedge clk_i);
        #1;
        $display("TC4: Reset Active | C_out=%d (Expected 0)", C_out);

        #(CLK_PERIOD * 2);
        $finish;
    end

endmodule