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
    input  logic        load_B,
    input  logic        row_major,
    input  logic        enable,
    input  logic [15:0] data_in_A  [ROWS-1:0], // Inputs from the left
    input  logic [15:0] data_in_PS [ROWS-1:0],
    output logic [15:0] data_out_A [ROWS-1:0], // Outputs to the right
    output logic [15:0] data_out_PS[ROWS-1:0]
);
    genvar i;
    generate
        for (i = 0; i < ROWS; i = i + 1) begin : pe_instances
            PE_final pe_cell (
                .clk_i             (clk),
                .reset             (reset),
                .load_B_in            (load_B),
                .B_is_row_major_in (row_major),
                .enable            (enable),
                .A_in         (data_in_A[i]),
                .A_out        (data_out_A[i]),
                .PS_in        (data_in_PS[i]),
                .PS_out       (data_out_PS[i])
            );
        end
    endgenerate
endmodule