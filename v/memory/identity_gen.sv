module identity_gen #(
    parameter int WIDTH_p = 256,
    localparam int BITS_PER_INT_lp = WIDTH_P / 8,
    localparam int ROWS_BITWIDTH_lp = 3
) (
    input logic [ROWS_BITWIDTH_lp-1:0] row_i,
    output logic [WIDTH_p-1:0] identity_o
);

    always_comb begin
        identity_o = '0;
        identity_o[(WIDTH_p - 1) - (BITS_PER_INT_lp * row_i) - (BITS_PER_INT_lp - 1)] = 1'b1;
    end

endmodule
