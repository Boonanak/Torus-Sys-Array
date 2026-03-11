// This module is a singluar node that is part of a transposer unit
// It takes 4 seperate data streams, and selects one to pass on
// Selects the output based on a row or column enable.
module tp_node #(parameter WIDTH_p = 8, // bitwidth of the stored data
             ) (
                input logic clk_i,
                input logic rst_n_i,
                input logic [WIDTH_p-1:0] data_pass_0_i, // data passed in from the mode 0 direction
                input logic [WIDTH_p-1:0] data_pass_1_i, // data passed in from the mode 1 direction
                input logic [WIDTH_p-1:0] data_shift_0_i, // data shifted in from mode 0 direction
                input logic [WIDTH_p-1:0] data_shift_1_i, // data shifted in from mode 1 direction
                input logic [1:0] row_en_i, // row_en_i[1] is enable, row_en_i[0] is the select bit. sel 0 = pass, 1 = shift
                input logic [1:0] col_en_i, // col_en_i[1] is enable, col_en_i[0] is the select bit. sel 0 = pass, 1 = shift
                output logic [WIDTH_p-1:0] data_out
               );

    // Assign next output data based on the row and column enable signals
    always_ff @(posedge clk_i) begin
        if (!rst_n_i) begin
            data_out <= '0; 
        end else begin
            if (row_en_i[1]) // Top bit is the enable signal, bottom is select bit
                data_out <= row_en_i[0] ? data_shift_1_i : data_pass_1_i; // Rows are direction 1 (vertical) operation
            else if (col_en_i[1])
                data_out <= col_en_i[0] ? data_shift_0_i : data_pass_0_i; // columns are direction 0 (horiziontal) operation
            // else hold current value
            // Both enable bits being true is an invalid state (but it will resolve to row taking priority)
        end
    end

endmodule