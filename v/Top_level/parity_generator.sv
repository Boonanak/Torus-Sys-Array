// Generates the parity bit for the given bits_i
module parity_generator #(
    parameter WIDTH_p = 16
) (
    input logic [WIDTH_p-1:0] bits_i,
    output logic parity_o
); 

    always_comb begin
        parity_o = ^bits_i; // XOR reduction to calculate parity
    end

endmodule