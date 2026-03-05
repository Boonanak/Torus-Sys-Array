/*
Logic for actually configuring our systolic array. This module essentially come down to one big
generate statement that starts by generating a slice of the array (one column) and then setting up
the routing between said column and the next column. However the first chalenge we ecnounter in
doing this is that the order flips between ODD and EVEN columns. Therefore after generating the
slice we check if the index of the current column odd, if it is then we execute the first pattern,
if it is not then we execute the second pattern, thereby swapping the routing of A and PS from
column to column. At the end of this generate statement if we are on the last column then we
handle it differently as each PE doesn't have to obey the pattern anymore. At this point we
exit the generate statement for that column and move on to the next. 

NOTE THIS IS CURRENTLY SPECIFIC FOR A 4X4 MATRIX
*/
`include "../PE/PE_pkg.sv" // There may be a more robust way to do this

import PE_pkg::*;

module sys_array #(
    // Probably cleaner for just a single parameter here as the  matrices will be square and then
    // divide to rows and cols within the module itself
    parameter ROWS = 4,
    parameter COLS = 4
)(
    input  logic        clk,
    input  logic        reset,
    input  logic        load_B_A,
    input  logic        load_B_PS,
    
    // Data enters from the LEFTmost side of array
    input  int8_t       A_in_left   [ROWS-1:0],
    input  int16_t PS_in_left  [ROWS-1:0],
    
    // Data exits from the RIGHTmost side of array
    output int8_t       A_out_right  [ROWS-1:0],
    output int16_t PS_out_right [ROWS-1:0]
);

    // col_in_X[j] is the data waiting to enter the left side of column j
    int8_t       col_in_A  [COLS:0][ROWS-1:0];
    logic [15:0] col_in_PS [COLS:0][ROWS-1:0];

    // Initial inputs feed into the first column (j=0)
    assign col_in_A[0]  = A_in_left;
    assign col_in_PS[0] = PS_in_left;

    genvar j;
    generate
        for (j = 0; j < COLS; j = j + 1) begin : column_loop
            
            // Outputs emerging from the right side of the current column
            int8_t       col_out_A  [ROWS-1:0];
            logic [15:0] col_out_PS [ROWS-1:0];

            // Instantiate the column slice
            col_gen #(.ROWS(ROWS)) column_inst (
                .clk       (clk),
                .reset     (reset),
                .load_B_A  (load_B_A),
                .load_B_PS (load_B_PS),
                .data_in_A (col_in_A[j]),
                .data_in_PS(col_in_PS[j]),
                .data_out_A(col_out_A),
                .data_out_PS(col_out_PS)
            );

            // Braided Wiring (Connecting right side of j to left side of j+1)
            if (j < COLS-1) begin : internal_routing
                // Logic for Column j -> Column j+1
                // We use (j+1) for the modulo check to maintain the Odd/Even transition logic
                if (((j+1) % 2) != 0) begin : braid_pattern_1
                    // Pattern: Row 1 A-Direct, B-Down | Row 2 A-Down, B-Up | Row 3 A-Up, B-Down | Row 4 A-Direct, B-Up
                    assign col_in_A [j+1][0] = col_out_A[0];  assign col_in_PS[j+1][1] = col_out_PS[0];
                    assign col_in_A [j+1][2] = col_out_A[1];  assign col_in_PS[j+1][0] = col_out_PS[1];
                    assign col_in_A [j+1][1] = col_out_A[2];  assign col_in_PS[j+1][3] = col_out_PS[2];
                    assign col_in_A [j+1][3] = col_out_A[3];  assign col_in_PS[j+1][2] = col_out_PS[3];
                end else begin : braid_pattern_2
                    // Pattern: Flipped logic for the next column jump
                    assign col_in_A [j+1][1] = col_out_A[0];  assign col_in_PS[j+1][0] = col_out_PS[0];
                    assign col_in_A [j+1][0] = col_out_A[1];  assign col_in_PS[j+1][2] = col_out_PS[1];
                    assign col_in_A [j+1][3] = col_out_A[2];  assign col_in_PS[j+1][1] = col_out_PS[2];
                    assign col_in_A [j+1][2] = col_out_A[3];  assign col_in_PS[j+1][3] = col_out_PS[3];
                end
            end else begin : last_column_exit
                // Final outputs from the right side of the last column
                assign A_out_right  = col_out_A;
                assign PS_out_right = col_out_PS;
            end
        end
    endgenerate

endmodule