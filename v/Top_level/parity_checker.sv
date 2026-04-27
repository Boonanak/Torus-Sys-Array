// is_parity_o is true if bits_i matches its parity_i, false otherwise
module parity_checker #(
    parameter WIDTH_p = 16
) (
    input logic [WIDTH_p-1:0] bits_i,
    input logic parity_i,
    output logic is_parity_o
);
    
    assign is_parity_o = (^bits_i) ~^ parity_i;

endmodule