module serial_shifter #(
    parameter WIDTH_p  = 1,
    parameter LENGTH_p = 1
) (
    input  logic clk_i,
    input  logic rst_n_i,
    input  logic enable_i,
    input  logic [WIDTH_p-1:0] shift_in_i,
    output logic [WIDTH_p-1:0] data_o
);

    logic [LENGTH_p-1:0][WIDTH_p-1:0] shift_reg;

    always_ff @(posedge clk_i) begin
        if (!rst_n_i) begin
            shift_reg <= '0;
            data_o    <= '0;
        end else if (enable_i) begin
            // Output the oldest element
            data_o <= shift_reg[LENGTH_p-1];
            if (LENGTH_p == 1) begin
                // No shifting possible — just replace the single element
                shift_reg[0] <= shift_in_i;
            end else begin
                // Normal shift for LENGTH_p >= 2
                shift_reg <= {shift_reg[LENGTH_p-2:0], shift_in_i};
            end
        end
    end

endmodule
