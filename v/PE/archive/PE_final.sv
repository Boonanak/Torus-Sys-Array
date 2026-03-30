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

    // register inputs
    logic [15:0] A_in_reg, PS_in_reg;
    logic enable_reg;
    logic row_major_reg, row_major_in_reg;
    logic row_major;
    logic load_B_reg; 
    // combinational A/B/PS values and its register for when enable=0
    int8_t A, A_reg, B, B_reg;
    int16_t PS, PS_reg;

    int16_t alu_result;

    // should never overflow the 17 bit unless control logic for A and B is messed up
    logic signed [16:0] intermediate;

    assign row_major = enable_reg ? row_major_in_reg : row_major_reg; 

    always_comb begin 
        if (load_B_reg) begin 
            A = A_reg;
            B = row_major ? A_in_reg[7:0] : PS_in_reg[7:0]; 
            PS = PS_reg;
        end else if (enable_reg) begin 
            A = row_major ? A_in_reg[7:0] : PS_in_reg[7:0];
            B = B_reg;
            PS = row_major ? PS_in_reg[15:0] : A_in_reg[15:0];
        end else begin 
            A = A_reg;
            B = B_reg;
            PS = PS_reg;
        end

        intermediate = A * B + PS;
        alu_result = (intermediate < -32768) ? 16'h8000 :
                     (intermediate > 32767) ? 16'h7FFF : intermediate[15:0];

        if (load_B_reg) begin 
            A_out = row_major ? {8'b0, B} : 16'b0;
            PS_out = row_major ? 16'b0 : {8'b0, B};
        end else begin 
            A_out = row_major ? {8'b0, A} : alu_result;
            PS_out = row_major ? alu_result : {8'b0, A};
        end
    end


    always_ff @(posedge clk_i) begin 
        if (reset) begin 
            A_reg           <= '0;
            B_reg           <= '0;
            PS_reg          <= '0;

            load_B_reg      <= '0;
            A_in_reg        <= '0;
            PS_in_reg       <= '0;
            enable_reg      <= '0;
            row_major_reg   <= '0;
        end
        else begin 
            A_reg           <= A;
            B_reg           <= B;
            PS_reg          <= PS;

            load_B_reg      <= load_B_in;
            A_in_reg        <= A_in;
            PS_in_reg       <= PS_in;
            enable_reg      <= enable;
            row_major_in_reg <= B_is_row_major_in;
            row_major_reg   <= row_major;
        end
    end

endmodule