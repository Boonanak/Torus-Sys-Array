// TwistMesh.sv — Twist-WS Mesh: N_p × N_p array of TwistPE
//
// Two interconnect paths:
//   BLACK (horizontal): PE(r,c) → PE(r,   c+1) — psum and weight
//   RED   (diagonal):   PE(r,c) → PE((r-1+N)%N, c+1) — ifmap and lock
//
// Compute pattern (always CP1):
//   ifmap on RED (diagonal),  psum on BLACK (horizontal)
//
// Load pattern (LP1 = A×B, row-major B):
//   weight on BLACK (horizontal),  lock on RED (diagonal)
//
// Registration:
//   weight, lock, propagate — registered INSIDE TwistPE
//   ifmap, psum             — registered BETWEEN PEs here (gated by
//                             col_valid, i.e. RegEnable behavior)
//   valid, last             — registered per column here
//
// Output: direct read from column N_p-1 (no de-braiding needed).

import PE_pkg::*;

module TwistMesh #(
     parameter N_p            = 4                                         // array dimension (must be power of 2)
    ,parameter INPUT_WIDTH_p  = 8
    ,parameter WEIGHT_WIDTH_p = 8
    // ,parameter OUTPUT_WIDTH_p = 19  // 19b mesh-internal psum (truncated to 16 outside)
    ,parameter OUTPUT_WIDTH_p = 32     // T2SA-MESH: int32 psum (no truncation outside)
)(
     input  logic                              clk_i
    ,input  logic                              reset_i

    // Column 0 inputs — one element per row
    ,input  logic signed [WEIGHT_WIDTH_p-1:0]  in_weight_i  [N_p-1:0]
    ,input  logic                              in_lock_i    [N_p-1:0]
    ,input  logic signed [INPUT_WIDTH_p-1:0]   in_ifmap_i   [N_p-1:0]
    ,input  logic signed [OUTPUT_WIDTH_p-1:0]  in_psum_i    [N_p-1:0]
    ,input  logic                              in_propagate_i
    ,input  logic                              in_valid_i
    ,input  logic                              in_last_i

    // Column N_p-1 outputs — one element per row
    ,output logic signed [OUTPUT_WIDTH_p-1:0]  out_psum_o   [N_p-1:0]
    ,output logic                              out_valid_o
    ,output logic                              out_last_o
);

    // ================================================================
    // PE interconnect wires — indexed [row][col]
    // ================================================================
    logic signed [WEIGHT_WIDTH_p-1:0] pe_in_weight  [N_p-1:0][N_p-1:0];
    logic signed [WEIGHT_WIDTH_p-1:0] pe_out_weight [N_p-1:0][N_p-1:0];
    logic                             pe_in_lock    [N_p-1:0][N_p-1:0];
    logic                             pe_out_lock   [N_p-1:0][N_p-1:0];
    logic signed [INPUT_WIDTH_p-1:0]  pe_in_ifmap   [N_p-1:0][N_p-1:0];
    logic signed [INPUT_WIDTH_p-1:0]  pe_out_ifmap  [N_p-1:0][N_p-1:0];
    logic signed [OUTPUT_WIDTH_p-1:0] pe_in_psum    [N_p-1:0][N_p-1:0];
    logic signed [OUTPUT_WIDTH_p-1:0] pe_out_psum   [N_p-1:0][N_p-1:0];
    logic                             pe_in_prop    [N_p-1:0][N_p-1:0];
    logic                             pe_out_prop   [N_p-1:0][N_p-1:0];

    // ================================================================
    // Valid pipeline — one register per column, horizontal
    // Reference: TwistMesh.scala lines 67-71
    //   col_valid(0) := io.in_valid
    //   for (c <- 1 until n)
    //     col_valid(c) := RegNext(col_valid(c - 1), false.B)
    // ================================================================
    logic col_valid_r [N_p-1:0];
    assign col_valid_r[0] = in_valid_i;
    for (genvar c = 1; c < N_p; c++) begin : gen_valid_pipe
        always_ff @(posedge clk_i) begin
            if (reset_i)
                col_valid_r[c] <= 1'b0;
            else
                col_valid_r[c] <= col_valid_r[c-1];
        end
    end

    // ================================================================
    // Last pipeline — same as valid, horizontal
    // Reference: TwistMesh.scala lines 78-81
    // ================================================================
    logic col_last_r [N_p-1:0];
    assign col_last_r[0] = in_last_i;
    for (genvar c = 1; c < N_p; c++) begin : gen_last_pipe
        always_ff @(posedge clk_i) begin
            if (reset_i)
                col_last_r[c] <= 1'b0;
            else
                col_last_r[c] <= col_last_r[c-1];
        end
    end

    // ================================================================
    // PE instantiation — flat N_p × N_p array
    // Reference: TwistMesh.scala line 60
    //   val pes = Seq.fill(n, n)(Module(new TwistPE(...)))
    // ================================================================
    for (genvar r = 0; r < N_p; r++) begin : gen_row
        for (genvar c = 0; c < N_p; c++) begin : gen_col
            TwistPE #(
                 .INPUT_WIDTH_p  (INPUT_WIDTH_p)
                ,.WEIGHT_WIDTH_p (WEIGHT_WIDTH_p)
                ,.OUTPUT_WIDTH_p (OUTPUT_WIDTH_p)
            ) u_pe (
                 .clk_i           (clk_i)
                ,.reset_i         (reset_i)
                ,.in_weight_i     (pe_in_weight [r][c])
                ,.out_weight_o    (pe_out_weight[r][c])
                ,.in_lock_i       (pe_in_lock   [r][c])
                ,.out_lock_o      (pe_out_lock  [r][c])
                ,.in_ifmap_i      (pe_in_ifmap  [r][c])
                ,.out_ifmap_o     (pe_out_ifmap [r][c])
                ,.in_psum_i       (pe_in_psum   [r][c])
                ,.out_psum_o      (pe_out_psum  [r][c])
                ,.in_propagate_i  (pe_in_prop   [r][c])
                ,.out_propagate_o (pe_out_prop  [r][c])
                ,.in_valid_i      (col_valid_r[c])                        // all PEs in column share col_valid
            );
        end
    end

    // ================================================================
    // WEIGHT routing: BLACK path (horizontal) — LP1
    //
    // Weight flows left-to-right in the SAME ROW.
    // Registration is INSIDE the PE (pass_reg_r), no register here.
    //
    // Reference: TwistMesh.scala lines 91-99
    //   pes(r)(0).io.in_weight := io.in_weight(r)
    //   pes(r)(c).io.in_weight := pes(r)(c-1).io.out_weight  [LP1]
    // ================================================================
    for (genvar r = 0; r < N_p; r++) begin : gen_weight_col0
        assign pe_in_weight[r][0] = in_weight_i[r];                       // column 0 from external input
    end
    for (genvar r = 0; r < N_p; r++) begin : gen_weight_horiz
        for (genvar c = 1; c < N_p; c++) begin : gen_weight_c
            assign pe_in_weight[r][c] = pe_out_weight[r][c-1];            // BLACK — same row, previous column
        end
    end

    // ================================================================
    // LOCK routing: RED path (diagonal) — LP1
    //
    // Lock flows diagonally: PE(r,c) receives from PE((r+1)%N, c-1).
    // Registration is INSIDE the PE (lock_delayed_r), no register here.
    //
    // Reference: TwistMesh.scala lines 103-111
    //   pes(r)(0).io.in_lock := io.in_lock(r)
    //   pes(r)(c).io.in_lock := pes((r+1)%n)(c-1).io.out_lock  [LP1]
    //
    // (r+1)%N means: to compute PE(r,c)'s lock input, look at row
    // (r+1)%N in the previous column. This is upward-diagonal with wrap.
    // ================================================================
    for (genvar r = 0; r < N_p; r++) begin : gen_lock_col0
        assign pe_in_lock[r][0] = in_lock_i[r];                           // column 0 from external input
    end
    for (genvar r = 0; r < N_p; r++) begin : gen_lock_diag
        for (genvar c = 1; c < N_p; c++) begin : gen_lock_c
            assign pe_in_lock[r][c] = pe_out_lock[(r+1)%N_p][c-1];        // RED — diagonal, (r+1)%N wrap
        end
    end

    // ================================================================
    // IFMAP routing: RED path (diagonal) with pipeline register
    //
    // Ifmap flows diagonally: PE(r,c) receives from PE((r+1)%N, c-1).
    // A pipeline register gated by col_valid_r sits BETWEEN PEs.
    // This implements the RegEnable from the Chisel code.
    //
    // Reference: TwistMesh.scala lines 116-119
    //   pes(r)(0).io.in_ifmap := io.in_ifmap(r)
    //   pes(r)(c).io.in_ifmap := RegEnable(
    //       pes((r+1)%n)(c-1).io.out_ifmap, col_valid(c-1))
    //
    // Why gated by col_valid_r[c-1]:
    //   When col_valid_r[c-1]=0, the source PE has no valid data yet.
    //   The register holds its previous value (prevents garbage).
    //   When col_valid_r[c-1]=1, the source PE has valid output —
    //   the register captures it.
    // ================================================================
    for (genvar r = 0; r < N_p; r++) begin : gen_ifmap_col0
        assign pe_in_ifmap[r][0] = in_ifmap_i[r];                         // column 0 from external input
    end
    for (genvar r = 0; r < N_p; r++) begin : gen_ifmap_diag
        for (genvar c = 1; c < N_p; c++) begin : gen_ifmap_c
            always_ff @(posedge clk_i) begin
                if (col_valid_r[c-1])                                     // gated — RegEnable behavior
                    pe_in_ifmap[r][c] <= pe_out_ifmap[(r+1)%N_p][c-1];    // RED — diagonal, (r+1)%N wrap
            end
        end
    end

    // ================================================================
    // PSUM routing: BLACK path (horizontal) with pipeline register
    //
    // Psum flows horizontally in the SAME ROW.
    // A pipeline register gated by col_valid_r sits BETWEEN PEs.
    //
    // Reference: TwistMesh.scala lines 122-126
    //   pes(r)(0).io.in_psum := io.in_psum(r)
    //   pes(r)(c).io.in_psum := RegEnable(
    //       pes(r)(c-1).io.out_psum, col_valid(c-1))
    // ================================================================
    for (genvar r = 0; r < N_p; r++) begin : gen_psum_col0
        assign pe_in_psum[r][0] = in_psum_i[r];                           // column 0 from external input
    end
    for (genvar r = 0; r < N_p; r++) begin : gen_psum_horiz
        for (genvar c = 1; c < N_p; c++) begin : gen_psum_c
            always_ff @(posedge clk_i) begin
                if (col_valid_r[c-1])                                     // gated — RegEnable behavior
                    pe_in_psum[r][c] <= pe_out_psum[r][c-1];              // BLACK — same row, previous column
            end
        end
    end

    // ================================================================
    // PROPAGATE routing: horizontal through PE chain
    //
    // Propagate flows left-to-right via PE's internal prop_delayed_r.
    // NO additional mesh-level register — the PE's 1-cycle delay IS
    // the pipeline register.
    //
    // ALL rows get the SAME propagate input at column 0.
    // PE chain delays it 1 cycle/column, so PE(r,c) sees propagate
    // c cycles after column 0.
    //
    // Reference: TwistMesh.scala lines 129-132
    //   pes(r)(0).io.in_propagate := io.in_propagate
    //   pes(r)(c).io.in_propagate := pes(r)(c-1).io.out_propagate
    // ================================================================
    for (genvar r = 0; r < N_p; r++) begin : gen_prop_col0
        assign pe_in_prop[r][0] = in_propagate_i;                         // all rows get same propagate
    end
    for (genvar r = 0; r < N_p; r++) begin : gen_prop_chain
        for (genvar c = 1; c < N_p; c++) begin : gen_prop_c
            assign pe_in_prop[r][c] = pe_out_prop[r][c-1];                // horizontal chain through PE regs
        end
    end

    // ================================================================
    // Outputs — from column N_p-1
    // No de-braiding needed. Torus diagonal produces correct ordering.
    //
    // Reference: TwistMesh.scala lines 135-138
    //   io.out_psum(r) := pes(r)(n-1).io.out_psum
    //   io.out_valid    := col_valid(n-1)
    //   io.out_last     := col_last(n-1)
    // ================================================================
    for (genvar r = 0; r < N_p; r++) begin : gen_output
        assign out_psum_o[r] = pe_out_psum[r][N_p-1];
    end
    assign out_valid_o = col_valid_r[N_p-1];
    assign out_last_o  = col_last_r[N_p-1];

endmodule
