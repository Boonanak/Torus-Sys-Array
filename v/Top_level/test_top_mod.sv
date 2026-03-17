module Top_level #(
    parameter int ring_width_p = 32,
    parameter int out_width_p = 64,
    parameter int id_p         = 0,
    parameter int DIM_p        = 4,
    parameter int WIDTH_p      = 8
)(
    input  logic                    clk_i,
    input  logic                    reset_i,

    input  logic                    v_i,
    input  logic [ring_width_p-1:0] data_i,
    output logic                    ready_o,
    input  logic                    in_major_mode,
    input  logic                    in_load_weight,

    output logic                    v_o,
    output logic [out_width_p-1:0] data_o,
    input  logic                    ready_i
);

    logic transpose_handshake_suceeded, sys_array_handshake_suceeded;
    logic transpose_matrix_1, transpose_matrix_2;
    logic [1:0] write_counter;

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            transpose_matrix_1 <= 1'b0;
            transpose_matrix_2 <= 1'b0;
            write_counter <= '0;
        end else begin
            if (write_counter == 2'b00 && v_i)
                transpose_matrix_2 <= ~in_load_weight; // Store the new transpose signal 
            if (transpose_handshake_suceeded)
                write_counter <= write_counter + 1'b1;
            if (sys_array_handshake_suceeded && write_counter == 2'b00)
                transpose_matrix_1 <= transpose_matrix_2; // update top matrix with stored tranpose signal
        end 
    end 

    assign transpose = transpose_matrix_1; // replace transpose_do_transpose with this signal transpose (feel free to rename)
    assign transpose_handshake_suceeded = transpose_valid_i && transpose_ready_o;
    assign sys_array_handshake_suceeded = transpose_valid_o && sys_transposer_ready;

endmodule