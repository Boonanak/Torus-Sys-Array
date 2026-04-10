module sys_array #(
     parameter DIM_p = 4
)
(  
     input  logic clk_i
    ,input  logic reset
    
    ,input  logic signed [7:0] A_in [DIM_p - 1 : 0]
    ,input  logic signed [7:0] B_in [DIM_p - 1 : 0]
    ,input  logic A_valid
    ,input  logic B_valid
    ,input  logic row_major
    ,input  logic transposer_valid_in
    ,output logic transposer_ready_out

    ,output logic [15:0] systolic_array_results [DIM_p - 1 : 0]
    ,input  logic output_buffer_ready_in
    ,output logic output_buffer_valid_out
);
    
    // better names??
    typedef enum logic[1:0] {
        ONE,
        TWO,
        THREE,
        FOUR
    } A_state_e;

    typedef enum logic[1:0] {
        ONE,
        TWO,
        THREE,
        FOUR
    } B_state_e;

    A_state_e ps_A, ns_A;
    B_state_e ps_B, ns_B;

    always_comb begin 
        // some complicated FSM logic to generate outputs:
        // - handshake signals
        // - control signals for PE (enable, rowmajor, etc)
    end

    always_ff @(posedge clk_i) begin 
        if (reset) begin 
            // set registers to 0
            // figure out initial state
        end else begin 
            ps_A <= ns_A;
            ps_B <= ns_B;
        end
    end

endmodule