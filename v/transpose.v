// A pipelined transpose module for a DIM_p x DIM_p matrix with WIDTH_p bit elements
// Supports transpose, rotate, and identiy operations based on control signals
module transpose #( parameter DIM_p = 8, // Dimensions of the matrix
                    parameter WIDTH_p = 8 // Width of each element in bits
                    parameter double_input_p = 0 // If set, the module accepts two elements per cycle for faster processing
                ) (
                    // STILL WORK IN PROGRESS - DO NOT USE
                    input logic clk_i, 
                    input logic rst_n_i, // Active low reset
                    input logic [1:0] op_i, // Operation selector: op[1] = transpose, op[0] = rotate
                    input logic [(WIDTH_p * (double_input_p + 1)) - 1:0] in_data, // Single or double element input
                    input logic [$clog2(DIM_p):0] in_addr, // Row for input element
                    input logic valid_i, // Input data is valid to be loaded in
                    output logic full_o, // Output data is valid shifting through the pipeline
                    output logic [WIDTH_p-1:0] out_data [DIM_p-1:0] // full column element output
                  );

endmodule