/*
Submodule to generate a single column of PE instances in the systolic array. Does not include any
actual logic for tieing the flow of partial sums and weights in the new pipette fashion. Will be
called on a certain number of times (depending on the size of the array).
*/
module col_gen #(
    parameter ROWS  = 4
)(
    input  logic        clk,
    input  logic        reset,
    input  logic        load_B_A,
    input  logic        load_B_PS,
    input  int8_t       data_in_A  [ROWS-1:0], // Inputs from the left
    input  logic [15:0] data_in_PS [ROWS-1:0],
    output int8_t       data_out_A [ROWS-1:0], // Outputs to the right
    output logic [15:0] data_out_PS[ROWS-1:0]
);
    genvar i;
    generate
        for (i = 0; i < ROWS; i = i + 1) begin : pe_instances
            PE_shared_B pe_cell (
                .clk_i             (clk),
                .reset             (reset),
                .load_B_through_A  (load_B_A),
                .load_B_through_PS (load_B_PS),
                .A_or_B_in         (data_in_A[i]),
                .A_or_B_out        (data_out_A[i]),
                .PS_or_B_in        (data_in_PS[i]),
                .PS_or_B_out       (data_out_PS[i])
            );
        end
    endgenerate
endmodule