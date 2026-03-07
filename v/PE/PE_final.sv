// RTL for Processing Element (PE) of a systolic array using shared wires for
//  matrix weights of B and partial sum.
// PE holds onto last weight of B it sees during load into B_reg,
//  and computes A_in * B_reg + partial sum in, and outputs it as a partial sum
//  for next PE in the line
// Naming is done for row major data. the behavior of A and PS wire
//  swaps when we handle column major data.

import PE_pkg::*;

module PE_final
    (input  logic       clk_i
    ,input  logic       reset
    // control signals 
    ,input  logic       B_is_row_major_in
    ,input  logic       load_B_in
    ,input  logic       enable
    
    ,input  logic [15:0] A_in
    ,input  logic [15:0] PS_in

    ,output logic [15:0] A_out
    ,output logic [15:0] PS_out
    );

    // parsed inputs
    int8_t A;
    int8_t B, B_reg;  
    int16_t PS;

    logic load_B, B_is_row_major;
    logic [15:0] A_reg, PS_reg;

    int16_t alu_result;

    // should never overflow the 17 bit unless control logic for A and B is messed up
    logic signed [16:0] intermediate;

    always_comb begin 
        intermediate = A * B + PS;
        alu_result = (intermediate < -32768) ? 16'h8000 :
                     (intermediate > 32767) ? 16'h7FFF : intermediate[15:0];

        if (load_B) begin 
            A_out  = B_is_row_major ? {8'b0, B} : 16'b0;
            PS_out = B_is_row_major ? 16'b0 : {8'b0, B};
        end else begin 
            A_out  = B_is_row_major ? {8'b0, A} : alu_result;
            PS_out = B_is_row_major ? alu_result : {8'b0, A}; 
        end
    end

    always_comb begin
        if (load_B) begin 
            A = '0;
            PS = '0;
            // B is passed via weight wire in row major, and partial sum wire in column major
            B = B_is_row_major ? A_reg[7:0] : PS_reg[7:0]; 
        end
        else begin 
            A = (B_is_row_major) ? A_reg[7:0] : PS_reg[7:0];
            PS = (B_is_row_major) ? PS_reg : A_reg;
            B = B_reg;
        end
    end

    always_ff @(posedge clk_i) begin 
        if (reset) begin 
            A_reg   <= '0;
            B_reg   <= '0;
            PS_reg  <= '0;
            load_B  <= '0;
            B_is_row_major <= '0;
        end
        else begin 
            load_B  <= enable ? load_B_in : load_B;
            B_is_row_major <= enable ? B_is_row_major_in : B_is_row_major;
            A_reg   <= enable ? A_in : A_reg;
            PS_reg  <= enable ? PS_in : PS_reg;
            B_reg   <= load_B ? B : B_reg;
        end
    end

endmodule