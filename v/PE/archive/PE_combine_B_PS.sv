// RTL for Processing Element (PE) of a systolic array using shared wires for
//   matrix weights of B and partial sum.
// PE holds onto last weight of B it sees during load into B_reg,
//   and computes A_in * B_reg + partial sum in, and outputs it as a partial sum
//   for next PE in the line.
// Interpret shared_B_PS signals as B if load_B is true, and PS if load_B is false
// top 8 bits of shared_B_PS signals are zero'd out if it is interpreted as B for safety
//
// Questions to answer: is there more efficient way to propagate load_B?
//                      currently, it is broadcasted to every PE and there needs to
//                      be a wire to each PE. maybe encode some info onto A during load.. maybe.
import PE_pkg::*;

module PE_combine_B_PS
    (input  logic       clk_i
    ,input  logic       reset
    ,input  logic       load_B       
    ,input  int8_t      A_in
    ,output int8_t      A_out
    // shared inputs for B and Partial Sum (PS)
    ,input  logic [15:0]    shared_B_PS_in
    ,output logic [15:0]    shared_B_PS_out
    );

    int8_t B_reg;

    int8_t B_in;
    int16_t alu_result;
    int16_t partial_sum_in;

    assign B_in = load_B ? shared_B_PS_in[7:0] : B_reg;
    assign partial_sum_in = load_B ? 16'b0 : shared_B_PS_in;
    assign alu_result = A_in * B_reg + partial_sum_in; 
    
    always_ff @(posedge clk_i) begin
        if (reset) begin
            A_out <= '0;
            B_reg <= '0;
            shared_B_PS_out <= '0;
        end else begin
            A_out <= A_in;
            B_reg <= B_in;
            shared_B_PS_out <= load_B ? {8'b0, B_in} : alu_result;
        end
    end
    
endmodule