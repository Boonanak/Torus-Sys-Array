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

module PE_shared_B
    (input  logic       clk_i
    ,input  logic       reset
    ,input  logic       load_B_through_A
    ,input  logic       load_B_through_PS       
    ,input  int8_t      A_or_B_in
    ,output int8_t      A_or_B_out
    // shared inputs for B and Partial Sum (PS)
    ,input  logic [15:0]    PS_or_B_in
    ,output logic [15:0]    PS_or_B_out
    );

    // parsed inputs
    int8_t A;
    int8_t B;  
    int16_t PS;

    // register to store B for systolic array operations
    // no register is needed for A and PS since they always flow through
    int8_t B_reg;  

    assign A = load_B_through_A ? 8'b0 : A_or_B_in;
    assign B = load_B_through_A ? A_or_B_in :
               load_B_through_PS ? PS_or_B_in : B_reg;
    assign PS = load_B_through_PS ? 16'b0 : PS_or_B_in;

    int16_t alu_result;
    assign alu_result = A * B_reg + PS;

    always_ff @(posedge clk_i) begin 
        if (reset) begin 
            B_reg <= 8'b0;
            A_or_B_out <= 8'b0;
            PS_or_B_out <= 16'b0;
        end
        B_reg <= B;
        A_or_B_out <= load_B_through_A ? B : A;

        // probably ok to skip on zeroing out if loading occurs through A
        // but I am lazy to rewrite testfile and this adds some more control at least.
        PS_or_B_out <= load_B_through_PS ? {8'b0, B} :
                       load_B_through_A ? 16'b0 : alu_result;
    end

endmodule