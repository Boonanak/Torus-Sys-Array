// TwistPE_tb.sv — Self-checking testbench for TwistPE
// Tests:
//   1. Weight load + MAC computation
//   2. Double-buffering (back-to-back matmuls)
//   3. Stall behavior (in_valid=0 freezes all regs)
//   4. Combinational ifmap pass-through
//   5. Weight relay (pass_reg)

`timescale 1ns / 1ps

module TwistPE_tb;

    // ================================================================
    // Waveform dump
    // ================================================================
    initial begin
        $fsdbDumpfile("TwistPE_tb.fsdb");
        $fsdbDumpvars("+all");
    end

    // ================================================================
    // Clock and reset
    // ================================================================
    localparam PERIOD = 10;
    logic clk_i;
    initial begin
        clk_i = 0;
        forever #(PERIOD/2) clk_i = ~clk_i;
    end

    logic reset_i;
    initial begin
        reset_i = 1'b1;
        repeat(5) @(posedge clk_i);
        reset_i = 1'b0;
    end

    // ================================================================
    // DUT signals
    // ================================================================
    logic signed [7:0]  in_weight;
    logic signed [7:0]  out_weight;
    logic               in_lock;
    logic               out_lock;
    logic signed [7:0]  in_ifmap;
    logic signed [7:0]  out_ifmap;
    logic signed [15:0] in_psum;
    logic signed [15:0] out_psum;
    logic               in_propagate;
    logic               out_propagate;
    logic               in_valid;

    TwistPE #(
         .INPUT_WIDTH_p  (8)
        ,.WEIGHT_WIDTH_p (8)
        ,.OUTPUT_WIDTH_p (16)
    ) DUT (
         .clk_i           (clk_i)
        ,.reset_i         (reset_i)
        ,.in_weight_i     (in_weight)
        ,.out_weight_o    (out_weight)
        ,.in_lock_i       (in_lock)
        ,.out_lock_o      (out_lock)
        ,.in_ifmap_i      (in_ifmap)
        ,.out_ifmap_o     (out_ifmap)
        ,.in_psum_i       (in_psum)
        ,.out_psum_o      (out_psum)
        ,.in_propagate_i  (in_propagate)
        ,.out_propagate_o (out_propagate)
        ,.in_valid_i      (in_valid)
    );

    // ================================================================
    // Test infrastructure
    // ================================================================
    integer test_pass;
    integer test_fail;

    task automatic check_psum(input signed [15:0] expected, input string msg);
        if (out_psum !== expected) begin
            $error("FAIL [%s]: out_psum=%0d, expected=%0d", msg, out_psum, expected);
            test_fail++;
        end else begin
            $display("PASS [%s]: out_psum=%0d", msg, out_psum);
            test_pass++;
        end
    endtask

    task automatic check_signal(input logic [15:0] actual, input logic [15:0] expected, input string msg);
        if (actual !== expected) begin
            $error("FAIL [%s]: got=%0d, expected=%0d", msg, actual, expected);
            test_fail++;
        end else begin
            $display("PASS [%s]: got=%0d", msg, actual);
            test_pass++;
        end
    endtask

    // ================================================================
    // Main test sequence
    // ================================================================
    initial begin
        test_pass = 0;
        test_fail = 0;

        // Default inputs
        in_weight    = 0;
        in_lock      = 0;
        in_ifmap     = 0;
        in_psum      = 0;
        in_propagate = 0;
        in_valid     = 0;

        // Wait for reset to deassert
        @(negedge reset_i);
        @(posedge clk_i);

        // ============================================================
        // TEST 1: Weight load + MAC
        // Load weight=5 into buffer2 (prop=0 → inactive=buffer2)
        // Then compute with prop=1 (active=buffer2=5)
        // ============================================================
        $display("\n=== TEST 1: Weight load + MAC ===");

        // Cycle A: present weight, no lock yet
        in_valid = 1; in_weight = 5; in_lock = 0; in_propagate = 0;
        in_ifmap = 3; in_psum = 0;
        @(posedge clk_i); #1;
        // prop=0 → weight_sel=buffer1=0 → out_psum = 0 + 3*0 = 0
        check_psum(16'sd0, "T1 pre-lock MAC (buffer1=0)");

        // Cycle B: lock rises → capture weight=5 into buffer2
        in_lock = 1; in_weight = 5;
        @(posedge clk_i); #1;
        // lock_rise=1, prop=0 → buffer2 <= 5
        // But THIS cycle still computes with buffer1=0
        // (buffer2 is captured at posedge, used next cycle)
        // Actually: weight_sel uses in_propagate combinationally,
        // prop=0 → buffer1. buffer1 is still 0. So out_psum = 0+3*0=0
        check_psum(16'sd0, "T1 lock-rise cycle (buffer1 still 0)");

        // Cycle C: lock falls, switch to prop=1 (now buffer2=5 is active)
        in_lock = 0; in_propagate = 1; in_ifmap = 3; in_psum = 10;
        @(posedge clk_i); #1;
        // prop=1 → weight_sel=buffer2=5 → out_psum = 10 + 3*5 = 25
        check_psum(16'sd25, "T1 compute with buffer2=5");

        // ============================================================
        // TEST 2: Double-buffering (load into buffer1 while using buf2)
        // prop=1 → active=buffer2, inactive=buffer1
        // Lock to load weight=7 into buffer1
        // Then switch to prop=0 to use buffer1=7
        // ============================================================
        $display("\n=== TEST 2: Double-buffering ===");

        // Load weight=7 into buffer1 (prop=1 → inactive=buffer1)
        in_lock = 1; in_weight = 7; in_propagate = 1;
        in_ifmap = 2; in_psum = 0;
        @(posedge clk_i); #1;
        // lock_rise=1 (was 0 last cycle), prop=1 → buffer1 <= 7
        // This cycle: prop=1 → weight_sel=buffer2=5 → out_psum=0+2*5=10
        check_psum(16'sd10, "T2 load buf1 while using buf2");

        // Lock falls
        in_lock = 0; in_weight = 0;
        @(posedge clk_i); #1;

        // Switch to prop=0 → active=buffer1=7
        in_propagate = 0; in_ifmap = 4; in_psum = 0;
        @(posedge clk_i); #1;
        // prop=0 → weight_sel=buffer1=7 → out_psum = 0 + 4*7 = 28
        check_psum(16'sd28, "T2 compute with buffer1=7");

        // Verify buffer2 still has 5 (not corrupted)
        in_propagate = 1; in_ifmap = 1; in_psum = 0;
        @(posedge clk_i); #1;
        // prop=1 → weight_sel=buffer2=5 → out_psum = 0 + 1*5 = 5
        check_psum(16'sd5, "T2 buffer2 still intact (=5)");

        // ============================================================
        // TEST 3: Stall behavior
        // Set in_valid=0 and verify all registers freeze
        // ============================================================
        $display("\n=== TEST 3: Stall behavior ===");

        // Record current outputs
        in_valid = 0; in_weight = 99; in_lock = 1; in_propagate = 0;
        in_ifmap = 50; in_psum = 100;
        @(posedge clk_i); #1;
        // in_valid=0: registers frozen, out_psum = in_psum (bypass)
        check_psum(16'sd100, "T3 stall: psum bypass");
        check_signal(16'(out_weight), 16'(8'sd0), "T3 stall: pass_reg frozen");

        // Stay stalled for 2 more cycles
        @(posedge clk_i); #1;
        @(posedge clk_i); #1;
        check_signal(16'(out_weight), 16'(8'sd0), "T3 stall: pass_reg still frozen");

        // Resume valid — pass_reg should now update
        in_valid = 1; in_lock = 0; in_weight = 42;
        @(posedge clk_i); #1;
        // pass_reg_r should have captured 42 at this posedge
        // But out_weight reads pass_reg_r which just got updated
        // We need to wait until AFTER the posedge for the reg to update
        // #1 already past posedge, so out_weight = pass_reg_r(new) = ??
        // Actually: at the posedge that just happened, pass_reg_r <= 42
        // But we're reading #1 after that posedge. For always_ff,
        // out_weight = pass_reg_r which was updated THIS posedge.
        // Hmm, need one more cycle for the registered output to show.
        // Actually pass_reg_r <= in_weight at THIS posedge. out_weight
        // = pass_reg_r. After #1 delay, the new value should be visible.

        // Wait one more cycle for clean check
        in_weight = 0;
        @(posedge clk_i); #1;
        // Now pass_reg_r should be 0 (captured this cycle), but
        // out_weight shows pass_reg_r updated to 0.
        // The 42 was captured in the PREVIOUS cycle's pass_reg_r.
        // Let me rethink: we want to check that after stall resumes,
        // the PE starts working again. The key check is that the
        // weight=99 during stall was NOT captured.
        // buffer2 should NOT have 99 (lock_rise was during stall).
        in_propagate = 0; in_ifmap = 1; in_psum = 0;
        @(posedge clk_i); #1;
        // prop=0 → buffer1=7 (unchanged from test 2)
        check_psum(16'sd7, "T3 buffer1 survived stall (=7)");

        in_propagate = 1; in_ifmap = 1; in_psum = 0;
        @(posedge clk_i); #1;
        // prop=1 → buffer2=5 (unchanged, lock during stall was ignored)
        check_psum(16'sd5, "T3 buffer2 survived stall (=5, lock ignored)");

        // ============================================================
        // TEST 4: Combinational ifmap pass-through
        // out_ifmap should change in the SAME cycle as in_ifmap
        // ============================================================
        $display("\n=== TEST 4: Combinational ifmap pass-through ===");

        in_ifmap = 8'sd42;
        #1;
        check_signal(16'(out_ifmap), 16'(8'sd42), "T4 ifmap combinational");
        in_ifmap = -8'sd10;
        #1;
        check_signal(16'(out_ifmap), 16'(-8'sd10), "T4 ifmap neg value");

        // ============================================================
        // TEST 5: Weight relay (pass_reg)
        // Send weight values and check out_weight 1 cycle later
        // ============================================================
        $display("\n=== TEST 5: Weight relay (pass_reg) ===");

        in_valid = 1; in_weight = 8'sd33; in_lock = 0;
        @(posedge clk_i); #1;
        // pass_reg_r just captured 33
        check_signal(16'(out_weight), 16'(8'sd33), "T5 pass_reg=33");

        in_weight = -8'sd20;
        @(posedge clk_i); #1;
        check_signal(16'(out_weight), 16'(-8'sd20), "T5 pass_reg=-20");

        in_weight = 8'sd0;
        @(posedge clk_i); #1;
        check_signal(16'(out_weight), 16'(8'sd0), "T5 pass_reg=0");

        // ============================================================
        // Summary
        // ============================================================
        $display("\n================================");
        $display("TwistPE Testbench Summary:");
        $display("  PASS: %0d", test_pass);
        $display("  FAIL: %0d", test_fail);
        $display("================================\n");

        if (test_fail > 0)
            $fatal(1, "TESTBENCH FAILED with %0d errors", test_fail);
        else
            $display("ALL TESTS PASSED");

        $finish;
    end

endmodule
