// A pipelined transpose module for a DIM_p x DIM_p matrix with WIDTH_p bit elements
// Supports transpose, rotate, and identiy operations based on control signals
// Takes in a full row of an input matrix and outputs a full column of the transposed matrix
// Op Codes:
// 00 - Identity (output = input)
// 01 - Roate 90 degrees clockwise only
// 10 - Transpose only
// 11 - Rotate 90 degrees clockwise and transpose
module transpose #( parameter DIM_p = 8, // Dimensions of the matrix (DIM_p x DIM_p)
                    parameter WIDTH_p = 8 // Width of each element in bits
                ) (
                    input logic clk_i, 
                    input logic rst_n_i, // Active low reset
                    input logic [1:0] op_i, // Operation selector: op_i[1] = transpose, op_i[0] = rotate
                    input logic [WIDTH_p-1:0] in_data [DIM_p-1:0], // Full row input data
                    input logic valid_i, // if the input row data is valid
                    input logic ready_i, // if the downstream module is ready to accept output data
                    ///////////////////////////////////////////////////////////////////////////////
                    output logic valid_o, // if the output column data is valid
                    output logic ready_o, // if the module is ready to accept new input data
                    output logic [WIDTH_p-1:0] out_data [DIM_p-1:0] // full column output data
                  );

endmodule