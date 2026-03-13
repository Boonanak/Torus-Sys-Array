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

NOTE THIS IS IS MY ATTEMPT AT A GENERALIZED VERSION, IT MAY NOT BE WORKING BUT THE IDEA IS THERE
*/

import PE_pkg::*;

module sys_array #(
    parameter ROWS = 4,
    parameter COLS = 4
)(
    input  logic        clk_i,
    input  logic        reset,
    input  logic        load_B,
    input  logic        row_major,
    
    // Data enters from the LEFTmost side of array
    input  int8_t       transposer_data   [ROWS-1:0],

    // Data exits from the RIGHTmost side of array
    output logic [15:0]      A_out_right  [ROWS-1:0],
    output logic [15:0]      PS_out_right [ROWS-1:0],

    input  logic        transposer_valid_in,
    output logic        transposer_ready_out,
    
    input  logic        output_buffer_ready_in,
    output logic        output_buffer_valid_out
);

    logic [15:0] result_buffer [ROWS-1:0];
    logic [15:0] col_in_A      [COLS-1:0][ROWS-1:0];
    logic [15:0] col_in_PS     [COLS-1:0][ROWS-1:0];

    // Control signals
    logic [COLS : 0] valid, valid_next;
    logic [COLS - 1 : 0] load_B_control, load_B_control_next;
    logic [COLS - 1 : 0] row_major_control, row_major_control_next;
    logic [COLS : 0] enable;

    logic fifo_ready_in, fifo_valid_out;

    always_comb begin
        enable[COLS] = ~valid[COLS]; 
        for (integer i = COLS - 1; i >= 0; i--) begin 
            enable[i] = enable[i+1] || !valid[i];
        end

        if (fifo_ready_in && fifo_valid_out) enable = '1;

        for (integer i = COLS; i >= 1; i--) begin 
            valid_next[i] = enable[i] ? valid[i - 1] : valid[i];
        end
        valid_next[0] = enable[0] ? 
                        ((transposer_valid_in && transposer_ready_out) ? ~load_B : 1'b0)
                        : valid[0];

        load_B_control_next = (transposer_valid_in && transposer_ready_out) ? 
                              (load_B ? {load_B_control[COLS-2:0], load_B} : {COLS{1'b0}}) 
                              : load_B_control;
        row_major_control_next = (transposer_valid_in && transposer_ready_out) ? {row_major_control[COLS - 2:0], row_major} : row_major_control;
    end

    assign transposer_ready_out = !(&valid) | (fifo_ready_in && fifo_valid_out);

    always_ff @(posedge clk_i) begin 
        if (reset) begin 
            valid             <= '0;
            load_B_control    <= '0;
            row_major_control <= '0;
        end else begin 
            valid             <= valid_next;
            load_B_control    <= load_B_control_next;
            row_major_control <= row_major_control_next;
        end
    end

    assign fifo_valid_out = valid[COLS-1];

    // Initialize first column input
    genvar i, j, r;
    generate
        for (i = 0; i < ROWS; i = i + 1) begin : col_fill
            assign col_in_A[0][ROWS - 1 - i] = {8'b0, transposer_data[i]};
            assign col_in_PS[0][ROWS - 1 - i] = 16'b0;
        end

        for (j = 0; j < COLS; j = j + 1) begin : column_loop
            logic [15:0] col_out_A  [ROWS-1:0];
            logic [15:0] col_out_PS [ROWS-1:0];

            col_gen #(.ROWS(ROWS)) column_inst (
                .clk       (clk_i),
                .reset     (reset),
                .load_B    (load_B_control_next[j]),
                .row_major (row_major_control_next[j]),
                .enable    (enable[j]),
                .data_in_A (col_in_A[j]),
                .data_in_PS(col_in_PS[j]),
                .data_out_A(col_out_A),
                .data_out_PS(col_out_PS)
            );

            if (j < COLS-1) begin : internal_routing
                for (r = 0; r < ROWS; r = r + 1) begin : row_routing
                    if (((j+1) % 2) != 0) begin : braid_pattern_1
                        // Generalizing Pattern 1: A-logic swaps neighbors on odd rows, PS on even
                        assign col_in_A [j+1][r]     = ((r % 2) == 0) ? col_out_A[r]   : col_out_A[r^1];
                        assign col_in_PS[j+1][r]     = ((r % 2) == 0) ? col_out_PS[r^1] : col_out_PS[r];
                    end else begin : braid_pattern_2
                        // Generalizing Pattern 2: Flipped neighbor swap
                        assign col_in_A [j+1][r]     = ((r % 2) == 0) ? col_out_A[r^1] : col_out_A[r];
                        assign col_in_PS[j+1][r]     = ((r % 2) == 0) ? col_out_PS[r]   : col_out_PS[r^1];
                    end
                end
            end else begin : last_column_exit
                assign A_out_right = col_out_A;
                // Generalizing the result_buffer reordering (mirroring the PS swap)
                for (r = 0; r < ROWS; r = r + 1) begin : final_res_map
                    assign result_buffer[r] = col_out_PS[r ^ 1];
                end
            end
        end
    endgenerate

    // FIFO logic with generalized widths
    logic [ROWS * 16 - 1 : 0] flattened_result_buffer, flattened_PS_out_right;
    always_comb begin 
        for (int k = 0; k < ROWS; k++) begin 
            flattened_result_buffer[k * 16 +: 16] = result_buffer[k];
            PS_out_right[k] = flattened_PS_out_right[k * 16 +: 16];
        end
    end

    bsg_fifo_1r1w_small_hardened #(.width_p(ROWS * 16), .els_p(COLS * 2), .ready_THEN_valid_p(1)) fifo 
        (.clk_i(clk_i), .reset_i(reset), .v_i(fifo_valid_out), .ready_o(fifo_ready_in), 
         .data_i(flattened_result_buffer), .v_o(output_buffer_valid_out), 
         .data_o(flattened_PS_out_right), .yumi_i(output_buffer_ready_in));

endmodule