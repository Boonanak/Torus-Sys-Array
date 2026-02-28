// SUBJECT TO CHANGE!!!!! just putting down some starting boilerplate code to begin from
// Processing Element used for Systolic Array
// supports INT8 operations with INT16 Accumulate values (overflow safe?)
// produces C_out (16bit) = C_in (16bit) + A * B (8bit * 8bit = 16bit)
// 
// Parameter description:
// OPERAND WIDTH: bit width of multiplied operands A and B
// ACCUMULATE_WIDTH: bit width of accumulated sum and output C.
//                   assumed to be enough with 2 * OPERAND_WIDTH.
//                   technically requires 2 * OPERAND_WIDTH + $CLOG2(SIZE OF SYSTOLIC ARRAY)

import PE_pkg::*;

module PE  // parametrize for ready/valid handshake interface
    (input      logic       clk_i
    ,input      logic       reset
    ,input      int8_t      A_in
    ,input      int8_t      B_in
    ,input      int16_t     Partial_Sum_in
    ,output     int8_t      A_out
    ,output     int8_t      B_out   // TODO: add logic to send B_out and Partial_Sum_out on same wires
    ,output     int16_t     Partial_Sum_out
    );

    // intermediate logic to connect to multiply module with pipelining in future.
    int16_t ALU_RESULT;
    assign ALU_RESULT.value = A_in.value * B_in.value + Partial_Sum_in.value; 

    always_ff @(posedge clk_i) begin
        if (reset) begin
            Partial_Sum_out <= '0;
            A_out <= '0;
            B_out <= '0;
        end else begin
            Partial_Sum_out <= ALU_RESULT;
            A_out <= A_in;
            B_out <= B_in;
        end
    end
    
endmodule