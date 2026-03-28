// PE compliant for pipette architecture with active lock pulse
// unlike previous iterations, systolic array must feed buffered inputs
// instead of buffering outputs with fifo
module Pipette_PE # (
     parameter PS_WIDTH = 16
    ,parameter AB_WIDTH = 8
    )
    (input logic clk_i
    ,input logic reset

    ,input logic row_major
    ,input logic enable_A
    ,input logic enable_B
    ,input logic active_lock_pulse_in

    ,output logic active_lock_pulse_out
    // A and PS wires named for row major, but needs to be 
    // intentionally swapped for column major data
    ,input logic [AB_WIDTH - 1:0]   B_in
    ,input logic [PS_WIDTH - 1:0]   A_in
    ,input logic [PS_WIDTH - 1:0]   PS_in

    ,output logic [AB_WIDTH - 1:0]  B_out
    ,output logic [PS_WIDTH - 1:0]  A_out
    ,output logic [PS_WIDTH - 1:0]  PS_out
    );

    logic signed [PS_WIDTH - 1:0] A, A_reg, PS, PS_reg;
    logic signed [AB_WIDTH - 1:0] B, B_reg, Potential_B, Potential_B_reg;

    logic signed [PS_WIDTH - 1:0] alu_result;
    logic signed [PS_WIDTH : 0]  overflow_safe_computation;

    always_comb begin 
        A = A_reg;
        B = B_reg;
        PS = PS_reg;
        Potential_B = Potential_B_reg;
        if (enable_A) begin 
            A = row_major ? A_in : PS_in;
            PS = row_major ? PS_in : A_in;
        end
        if (enable_B) begin 
            Potential_B = B_in;
        end
        if (active_lock_pulse_in) begin 
            B = Potential_B;
        end

        overflow_safe_computation = A * B + PS;
        // any way to write this parameterized and no magic number?
        alu_result = (overflow_safe_computation < -32768) ? 16'h8000 :
                     (overflow_safe_computation > 32767) ? 16'h7FFF : 
                     overflow_safe_computation[PS_WIDTH - 1:0];
    end

    assign B_out = Potential_B_reg;
    assign A_out = A_reg;
    assign PS_out = PS_reg;

    always_ff @(posedge clk_i) begin 
        if (reset) begin 
            A_reg <= '0;
            PS_reg <= '0;
            B_reg <= '0;
            Potential_B_reg <= '0;
            active_lock_pulse_out <= '0;
        end
        else begin 
            A_reg <= A;
            PS_reg <= alu_result;
            B_reg <= B;
            Potential_B_reg <= Potential_B;
            // pulse should move with enable_B signal
            active_lock_pulse_out <= enable_B ? active_lock_pulse_in : active_lock_pulse_out;
        end
    end

endmodule