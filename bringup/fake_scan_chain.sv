// fake_scan_chain.sv  --  stand-in for the chip's scan chain, for emulation only.
//
// A LEN-bit shift register with a recognizable starting pattern. With scan_en high every
// clock edge shifts it (scan_in enters at bit 0, scan_out is the top bit, so the first bit
// read is bit LEN-1). With scan_en low it holds, except that the low 16 bits count up on
// every clock: a stand-in for functional state that changes while the chip runs, so you can
// see that a dump reflects the moment the clock stopped and that the state survives a dump.
module fake_scan_chain #(
    parameter int LEN = 1024            // must be >= 32
)(
     input  logic clk_i
    ,input  logic scan_en_i
    ,input  logic scan_in_i
    ,output logic scan_out_o
);
    localparam logic [63:0] PAT = 64'hA5C3_0F1E_9B6D_7248;
    logic [LEN-1:0] sr = {((LEN + 63) / 64){PAT}};

    always_ff @(posedge clk_i) begin
        if (scan_en_i) sr <= {sr[LEN-2:0], scan_in_i};
        else           sr[15:0] <= sr[15:0] + 16'd1;
    end

    assign scan_out_o = sr[LEN-1];
endmodule
