// Generates a row of the idenity matrix of the specified WIDTH
// Assumes the following endianness (fixed at 8x8 matrix, variable int width):
// int [WIDTH_p-1:0]
// row [0:7]
// matrix [0:7]
module identity_gen #(
    parameter int WIDTH_p = 256, // number of bits per row, assumed to be 8 x int type (ie INT16)
    localparam int BITS_PER_INT_lp = WIDTH_P / 8, // how bit an int is
    localparam int ROWS_BITWIDTH_lp = 3 // number of bits to store 0-7
) (
    input logic [ROWS_BITWIDTH_lp-1:0] row_i,
    output logic [WIDTH_p-1:0] identity_o
);

    // Synthesizes to a 3:8 decoder and 8 muxes on a vector of 0s
    always_comb begin
        identity_o = '0;
        // finds the bottom bit of the row_i-ith int and sets it to 1, with endianness [0:7]
        identity_o[(WIDTH_p - 1) - (BITS_PER_INT_lp * row_i) - (BITS_PER_INT_lp - 1)] = 1'b1;
    end

endmodule