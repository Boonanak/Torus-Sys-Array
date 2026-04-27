// TwistPE.sv — Twist-WS Processing Element
//
// Three internal data registers:
//   buffer1_r, buffer2_r : weight double-buffers (selected by propagate)
//   pass_reg_r           : weight pass-through relay (1-cycle delay)
// Two internal control registers:
//   lock_delayed_r       : lock pipeline (1-cycle delay)
//   prop_delayed_r       : propagate pipeline (1-cycle delay)
//
// Double-buffer convention (matches Chisel reference):
//   propagate=0 : compute with buffer1 (active), load into buffer2
//   propagate=1 : compute with buffer2 (active), load into buffer1
//
// Weight loading:
//   in_weight flows through pass_reg_r (1-cycle delay, frozen on stall).
//   in_lock propagates via lock_delayed_r (1-cycle delay, frozen on stall).
//   On lock rising edge, in_weight is captured DIRECTLY into the inactive
//   buffer. (in_weight and in_lock arrive at the same cycle — both
//   travel c hops from column 0.)
//
// Compute:
//   out_psum = in_ifmap * weight_from_active_buffer + in_psum (valid)
//   out_psum = in_psum                                        (!valid)
//   out_ifmap = in_ifmap  (COMBINATIONAL — pipeline regs in TwistMesh)

import PE_pkg::*;

module TwistPE #(
     parameter INPUT_WIDTH_p  = 8
    ,parameter WEIGHT_WIDTH_p = 8
    ,parameter OUTPUT_WIDTH_p = 19  // 19b psum (8 partial-sums of int8×int8 = 18b max, +1 sign)
)(
     input  logic                              clk_i
    ,input  logic                              reset_i

    // Weight load path — registered INSIDE PE via pass_reg_r
    ,input  logic signed [WEIGHT_WIDTH_p-1:0]  in_weight_i
    ,output logic signed [WEIGHT_WIDTH_p-1:0]  out_weight_o

    // Lock path — registered INSIDE PE via lock_delayed_r
    ,input  logic                              in_lock_i
    ,output logic                              out_lock_o

    // Ifmap path — COMBINATIONAL pass-through
    ,input  logic signed [INPUT_WIDTH_p-1:0]   in_ifmap_i
    ,output logic signed [INPUT_WIDTH_p-1:0]   out_ifmap_o

    // Psum path — COMBINATIONAL: MAC result when valid, bypass otherwise
    ,input  logic signed [OUTPUT_WIDTH_p-1:0]  in_psum_i
    ,output logic signed [OUTPUT_WIDTH_p-1:0]  out_psum_o

    // Propagate path — registered INSIDE PE via prop_delayed_r
    ,input  logic                              in_propagate_i
    ,output logic                              out_propagate_o

    // Valid — gates ALL register updates; when 0, everything freezes
    ,input  logic                              in_valid_i
);

    // ================================================================
    // Registers — 3 data + 2 control = 5 total
    // ================================================================
    logic signed [INPUT_WIDTH_p-1:0]  buffer1_r;
    logic signed [INPUT_WIDTH_p-1:0]  buffer2_r;
    logic signed [WEIGHT_WIDTH_p-1:0] pass_reg_r;
    logic                             lock_delayed_r;
    logic                             prop_delayed_r;

    // ================================================================
    // Lock rising-edge detection
    // Reference: TwistPE.scala line 70
    //   val lock_rise = io.in_lock && !lock_delayed
    //
    // Why rising-edge (not level):
    //   Lock propagates through the PE chain (1 hop/cycle via RED path).
    //   Each PE sees lock go 0→1→0. Only 0→1 triggers capture.
    //   Level-sensitive would re-capture on the same high pulse.
    //
    // Why in_lock_i (not lock_delayed_r):
    //   in_lock_i and in_weight_i arrive at the same cycle (both travel
    //   c hops). Comparing in_lock_i against lock_delayed_r gives the
    //   rising edge at the exact cycle the correct weight arrives.
    // ================================================================
    logic lock_rise;
    assign lock_rise = in_lock_i & ~lock_delayed_r;

    // ================================================================
    // Weight selection for MAC
    // Reference: TwistPE.scala line 97
    //   val weight_sel = Mux(io.in_propagate === 0.U, buffer1, buffer2)
    //
    // Uses in_propagate_i DIRECTLY (combinational), NOT prop_delayed_r.
    // prop_delayed_r is the OUTPUT to the next PE in the chain.
    // The current PE uses in_propagate_i for its own computation.
    // ================================================================
    logic signed [INPUT_WIDTH_p-1:0] weight_sel;
    assign weight_sel = (in_propagate_i == 1'b0) ? buffer1_r
                                                 : buffer2_r;

    // ================================================================
    // MAC computation
    // Reference: TwistPE.scala lines 98-107
    //   mac_unit.io.in_a := io.in_ifmap
    //   mac_unit.io.in_b := weight_sel
    //   mac_unit.io.in_c := io.in_psum
    //   io.out_psum := mac_unit.io.out_d  (when valid)
    //   io.out_psum := io.in_psum         (otherwise)
    //
    // Overflow detection: (OUTPUT_WIDTH_p+1) bits, then saturate.
    // Matches Pipette_PE.sv saturation style.
    // ================================================================
    logic signed [OUTPUT_WIDTH_p:0] mac_full;
    assign mac_full = in_psum_i + (in_ifmap_i * weight_sel);

    logic signed [OUTPUT_WIDTH_p-1:0] mac_result;
    always_comb begin
        if (mac_full < -signed'((OUTPUT_WIDTH_p+1)'(2**(OUTPUT_WIDTH_p-1))))
            mac_result = {1'b1, {(OUTPUT_WIDTH_p-1){1'b0}}};      // saturate min
        else if (mac_full > signed'((OUTPUT_WIDTH_p+1)'(2**(OUTPUT_WIDTH_p-1) - 1)))
            mac_result = {1'b0, {(OUTPUT_WIDTH_p-1){1'b1}}};      // saturate max
        else
            mac_result = mac_full[OUTPUT_WIDTH_p-1:0];
    end

    // ================================================================
    // Combinational outputs
    //
    // CRITICAL: out_ifmap_o and out_psum_o are COMBINATIONAL.
    // Pipeline registers for ifmap/psum are in TwistMesh BETWEEN PEs.
    // This differs from Pipette_PE where A_out/PS_out are registered.
    //
    // out_weight_o, out_lock_o, out_propagate_o are REGISTERED (driven
    // by pass_reg_r, lock_delayed_r, prop_delayed_r respectively).
    // Reference: TwistPE.scala lines 111-114
    // ================================================================
    assign out_ifmap_o     = in_ifmap_i;                                  // combinational pass-through
    assign out_psum_o      = in_valid_i ? mac_result : in_psum_i;         // MAC when valid, bypass otherwise
    assign out_weight_o    = pass_reg_r;                                  // registered via pass_reg_r
    assign out_lock_o      = lock_delayed_r;                              // registered via lock_delayed_r
    assign out_propagate_o = prop_delayed_r;                              // registered via prop_delayed_r

    // ================================================================
    // Sequential logic
    //
    // ALL registers gated by in_valid_i. When in_valid_i=0, EVERYTHING
    // freezes. This enables the drain phase: after weight loading, the
    // controller keeps in_valid_i=1 for N-1 extra cycles so lock/weight
    // continue propagating. If a stall occurs, propagation pauses.
    //
    // Reference: TwistPE.scala lines 69-91
    //   val lock_delayed = RegEnable(io.in_lock, false.B, io.in_valid)
    //   val prop_delayed = RegEnable(io.in_propagate, io.in_valid)
    //   when(io.in_valid) { pass_reg := io.in_weight }
    //   when(lock_rise && io.in_valid) { buffer <= in_weight }
    // ================================================================
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            buffer1_r      <= '0;
            buffer2_r      <= '0;
            pass_reg_r     <= '0;
            lock_delayed_r <= 1'b0;
            prop_delayed_r <= 1'b0;
        end
        else if (in_valid_i) begin
            // Weight pass-through: always update when valid
            // Relays weight to next PE in the horizontal chain.
            // Reference: TwistPE.scala lines 76-78
            pass_reg_r <= in_weight_i;

            // Lock pipeline: 1-cycle delay, frozen on stall
            // Reference: TwistPE.scala line 69
            lock_delayed_r <= in_lock_i;

            // Propagate pipeline: 1-cycle delay, frozen on stall
            // Reference: TwistPE.scala line 73
            prop_delayed_r <= in_propagate_i;

            // Weight capture on lock rising edge
            // Captures in_weight_i DIRECTLY (not pass_reg_r) because
            // in_weight_i and in_lock_i arrive at the same cycle —
            // both travel c hops from column 0.
            // Reference: TwistPE.scala lines 85-91
            if (lock_rise) begin
                if (in_propagate_i == 1'b0)
                    buffer2_r <= in_weight_i;                             // prop=0 → load INACTIVE buffer2
                else
                    buffer1_r <= in_weight_i;                             // prop=1 → load INACTIVE buffer1
            end
        end
        // else: !in_valid_i → ALL registers frozen (stall)
    end

endmodule
