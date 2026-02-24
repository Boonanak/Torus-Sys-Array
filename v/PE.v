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

module PE # (parameter OPERAND_WIDTH = 8
            ,parameter ACCUMULATE_WIDTH = 16)
    (input clk_i
    ,input reset
    ,input [OPERAND_WIDTH - 1 : 0] A
    ,input [OPERAND_WIDTH - 1 : 0] B
    ,input [ACCUMULATE_WIDTH - 1 : 0] C_in
    ,output [ACCUMULATE_WIDTH - 1 : 0] C_out
    );

    logic [ACCUMULATE_WIDTH - 1 : 0] C_out_reg;
    assign C_out = C_out_reg;

    // intermediate logic to connect to multiply module with pipelining in future.
    logic [ACCUMULATE_WIDTH - 1 : 0] ALU_RESULT;
    assign ALU_RESULT = A * B + C_in; 

    always_ff @(posedge clk) begin
        if (reset) begin
            C_out_reg <= '0;
        end else begin
            C_out_reg <= ALU_RESULT;
        end
    end
    
endmodule