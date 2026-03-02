module fifo #(  parameter WIDTH_p = 8,
                parameter DEPTH_p = 8
           ) (
                input logic clk_i,
                input logic rst_n_i,
                input logic write_i,
                input logic read_i,
                input logic [WIDTH_p-1:0] data_i,
                output logic [WIDTH_p-1:0] data_o,
                output logic full_o,
                output logic empty_o
             ); 

endmodule