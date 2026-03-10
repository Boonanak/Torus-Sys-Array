// Simple shift register 
// Use enable_i to shift in the shift_in_i value to the bottom
// Output current value in parellel
module shift_reg_simple #(parameter WIDTH_p = 8,
                          parameter LENGTH_p = 8
                       ) (
                        input logic clk_i,
                        input logic rst_n_i,
                        input logic enable_i,
                        input logic [WIDTH_p-1:0] shift_in_i, // value to shift in
                        output logic [WIDTH_p-1:0] data_out_o [LENGTH_p-1:0]
                       );

    // Move the top bits up 1 and shift in the new value at the bottom
    // Throw away top bit
    always_ff @(posedge clk_i) begin
        if (!rst_n_i) begin
            data_out_o <= '0; 
        end else if (enable_i) begin
            data_out_o <= {data_out_o[LENGTH_p-2:0], shift_in_i};
        end
    end

endmodule