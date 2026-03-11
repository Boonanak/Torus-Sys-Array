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
//`include "../PE/PE_pkg.sv" // There may be a more robust way to do this

import PE_pkg::*;

module sys_array #(
    // Probably cleaner for just a single parameter here as the  matrices will be square and then
    // divide to rows and cols within the module itself
    parameter ROWS = 4,
    parameter COLS = 4
    // might help to add parameter for data width?
)(
    input  logic        clk_i,
    input  logic        reset,
    input  logic        load_B,
    input  logic        row_major,
    

    // Data enters from the LEFTmost side of array
    input  int8_t      transposer_data   [ROWS-1:0],

    // Data exits from the RIGHTmost side of array
    output logic [15:0]      A_out_right  [ROWS-1:0],
    output logic [15:0]      PS_out_right [ROWS-1:0],

    input  logic        transposer_valid_in,
    output logic        transposer_ready_out,
    
    input  logic        output_buffer_ready_in,
    output logic        output_buffer_valid_out
);

    logic [15:0] result_buffer [ROWS-1:0];

    logic [15:0] col_in_A  [COLS-1:0][ROWS-1:0];
    logic [15:0] col_in_PS [COLS-1:0][ROWS-1:0];

    // control signals
    logic [COLS - 1 : 0] valid, valid_next;
    logic [COLS - 1 : 0] load_B_control, load_B_control_next;
    logic [COLS - 1 : 0] row_major_control, row_major_control_next;
    logic [COLS - 1 : 0] enable;

    logic fifo_ready_in, fifo_valid_out;

    always_comb begin
        enable[COLS - 1] = ~valid[COLS - 1]; 
        for (integer i = COLS - 2; i >= 0; i--) begin 
            enable[i] = enable[i+1] || !valid[i];
        end

        if (fifo_ready_in && fifo_valid_out) enable = '1;

        for (integer i = COLS - 1; i >= 1; i--) begin 
            valid_next[i] = enable[i] ? valid[i - 1] : valid;
        end
        valid_next[0] = enable[0] ? 
                        ((transposer_valid_in && transposer_ready_out) ? ~load_B : 1'b0)
                        : valid[0];

        load_B_control_next = (transposer_valid_in && transposer_ready_out) ? 
                              (load_B ? {load_B_control[COLS-2:0], load_B} : {COLS{1'b0}}) 
                              : load_B_control;
        row_major_control_next = (transposer_valid_in && transposer_ready_out) ? {row_major_control[2:0], row_major} : row_major_control;
    end

    assign transposer_ready_out = !(&valid) | (fifo_ready_in && fifo_valid_out);

    always_ff @(posedge clk_i) begin 
        if (reset) begin 
            valid                   <= '0;
            load_B_control          <= '0;
            row_major_control       <= '0;
            fifo_valid_out <= '0;
        end else begin 
            valid                   <= valid_next;
            load_B_control          <= load_B_control_next;
            row_major_control       <= row_major_control_next;
            fifo_valid_out <= valid[COLS-1];
        end
    end

    // initialize PE
    genvar i;
    generate
    for (i = 0; i < COLS; i = i + 1) begin : col_fill
        assign col_in_A[0][COLS - 1 - i] = {8'b0, transposer_data[i]};
        assign col_in_PS[0][COLS - 1 - i] = 16'b0;
    end
    endgenerate

    genvar j;
    generate
        for (j = 0; j < COLS; j = j + 1) begin : column_loop
            
            logic [15:0] col_out_A  [ROWS-1:0];
            logic [15:0] col_out_PS [ROWS-1:0];

            // Instantiate the column slice
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
                assign result_buffer[0] = col_out_PS[3];
                assign result_buffer[1] = col_out_PS[1];
                assign result_buffer[2] = col_out_PS[2];
                assign result_buffer[3] = col_out_PS[0];
            end
        end
    endgenerate

    logic fifo_yumi;
    assign fifo_yumi = output_buffer_ready_in;
    // always_ff @(posedge clk_i) begin 
    //     if (reset) begin 
    //         fifo_yumi <= '0;
    //     end
    //     else begin 
    //         fifo_yumi <= output_buffer_ready_in;
    //     end
    // end

    logic [COLS * 16 - 1 : 0] flattened_result_buffer, flattened_PS_out_right;
    always_comb begin 
        for (int i = 0; i < COLS; i++) begin 
            flattened_result_buffer[i * 16 +: 16] = result_buffer[i];
        end

        for (int i = 0; i < COLS; i++) begin 
            PS_out_right[i] = flattened_PS_out_right[i * 16 +: 16];
        end
    end

    // synchronous fifo, use ready then valid since thats what we expect from this thing!!!!
    // could probably parametrize width_p and els_p using COL/ROW params
    bsg_fifo_1r1w_small_hardened #(.width_p(ROWS * 16), .els_p(COLS * 2), .ready_THEN_valid_p(1)) fifo 
        (.clk_i(clk_i)
        ,.reset_i(reset)
        ,.v_i(fifo_valid_out)
        ,.ready_o(fifo_ready_in) 
        ,.data_i(flattened_result_buffer)
        ,.v_o(output_buffer_valid_out)
        ,.data_o(flattened_PS_out_right)
        ,.yumi_i(fifo_yumi)
        );
endmodule