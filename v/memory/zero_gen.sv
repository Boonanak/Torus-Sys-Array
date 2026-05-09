// Outputs a static vector of zeros of width WIDTH_p
module zero_gen #(
    parameter int WIDTH_p // output bitwidth
) (
    output logic [WIDTH_p-1:0] zero_o
);

    assign zero_o = '0;

endmodule
