`timescale 1ns/1ps

module memory_tb();

    // ---------------------------------------------------------
    // Parameters
    // ---------------------------------------------------------
    parameter DEPTH         = 64;
    parameter ELEMENTS      = 8;
    parameter W_I_WIDTH     = 8;
    parameter PSUM_WIDTH    = 16; 
    
    localparam W_I_VEC_WIDTH  = ELEMENTS * W_I_WIDTH;  // 64 bits
    localparam PSUM_VEC_WIDTH = ELEMENTS * PSUM_WIDTH; // 128 bits
    
    localparam ADDR_W         = $clog2(DEPTH);         
    localparam TAG_W          = (PSUM_WIDTH == 16) ? 2 : 3;
    localparam FULL_ADDR_W    = ADDR_W + TAG_W;

    // ---------------------------------------------------------
    // Signals
    // ---------------------------------------------------------
    logic clk, reset;
    
    // Local Ports
    logic weight_w_v, weight_r_v;
    logic [ADDR_W-1:0] weight_w_addr, weight_r_addr;
    logic [W_I_VEC_WIDTH-1:0] weight_w_data, weight_r_data;

    logic input_w_v, input_r_v;
    logic [ADDR_W-1:0] input_w_addr, input_r_addr;
    logic [W_I_VEC_WIDTH-1:0] input_w_data, input_r_data;

    logic psum_w_v, psum_r_v;
    logic [ADDR_W-1:0] psum_w_addr, psum_r_addr;
    logic [PSUM_VEC_WIDTH-1:0] psum_w_data, psum_r_data;

    // Chip IO Port
    logic chip_io_w_v, chip_io_r_v;
    logic [FULL_ADDR_W-1:0] chip_io_w_addr, chip_io_r_addr;
    logic [PSUM_VEC_WIDTH-1:0] chip_io_w_data, chip_io_r_data;

    // ---------------------------------------------------------
    // DUT Instantiation
    // ---------------------------------------------------------
    memory #(
        .memory_depth_p(DEPTH),
        .elements_per_vector_p(ELEMENTS),
        .weight_input_width_p(W_I_WIDTH),
        .psum_width_p(PSUM_WIDTH)
    ) dut (
         .clk_i             (clk)
        ,.reset             (reset)
        ,.weight_w_v_i      (weight_w_v)
        ,.weight_w_addr_i   (weight_w_addr)
        ,.weight_w_data_i   (weight_w_data)
        ,.weight_r_v_i      (weight_r_v)
        ,.weight_r_addr_i   (weight_r_addr)
        ,.weight_r_data_o   (weight_r_data)
        ,.input_w_v_i       (input_w_v)
        ,.input_w_addr_i    (input_w_addr)
        ,.input_w_data_i    (input_w_data)
        ,.input_r_v_i       (input_r_v)
        ,.input_r_addr_i    (input_r_addr)
        ,.input_r_data_o    (input_r_data)
        ,.psum_w_v_i        (psum_w_v)
        ,.psum_w_addr_i     (psum_w_addr)
        ,.psum_w_data_i     (psum_w_data)
        ,.psum_r_v_i        (psum_r_v)
        ,.psum_r_addr_i     (psum_r_addr)
        ,.psum_r_data_o     (psum_r_data)
        ,.chip_io_w_v_i     (chip_io_w_v)
        ,.chip_io_w_addr_i  (chip_io_w_addr)
        ,.chip_io_w_data_i  (chip_io_w_data)
        ,.chip_io_r_v_i     (chip_io_r_v)
        ,.chip_io_r_addr_i  (chip_io_r_addr)
        ,.chip_io_r_data_o  (chip_io_r_data)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        // --- Initialization ---
        reset = 1;
        {weight_w_v, weight_r_v, input_w_v, input_r_v, psum_w_v, psum_r_v} = '0;
        {chip_io_w_v, chip_io_r_v} = '0;
        repeat(5) @(posedge clk);
        reset = 0;
        @(posedge clk);

        // ---------------------------------------------------------
        // 1. LOCAL PORT ACCESSES (All three banks)
        // ---------------------------------------------------------
        $display("--- TEST 1: Local Port Accesses ---");
        
        // Weight Bank
        weight_w_v = 1; weight_w_addr = 'd10; weight_w_data = 64'h1111_2222_3333_4444;
        @(posedge clk); weight_w_v = 0;
        weight_r_v = 1; weight_r_addr = 'd10; @(posedge clk); #1;
        if (weight_r_data === 64'h1111_2222_3333_4444) $display("[PASS] Local Weight");
        else $display("[FAIL] Local Weight: %h", weight_r_data);
        weight_r_v = 0;

        // Input Bank
        input_w_v = 1; input_w_addr = 'd20; input_w_data = 64'h5555_6666_7777_8888;
        @(posedge clk); input_w_v = 0;
        input_r_v = 1; input_r_addr = 'd20; @(posedge clk); #1;
        if (input_r_data === 64'h5555_6666_7777_8888) $display("[PASS] Local Input");
        else $display("[FAIL] Local Input: %h", input_r_data);
        input_r_v = 0;

        // Psum Bank
        psum_w_v = 1; psum_w_addr = 'd30; psum_w_data = 128'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111;
        @(posedge clk); psum_w_v = 0;
        psum_r_v = 1; psum_r_addr = 'd30; @(posedge clk); #1;
        if (psum_r_data === 128'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111) $display("[PASS] Local Psum");
        else $display("[FAIL] Local Psum: %h", psum_r_data);
        psum_r_v = 0;

        // ---------------------------------------------------------
        // 2. CROSS PORT ACCESSES
        // ---------------------------------------------------------
        $display("\n--- TEST 2: Cross Port Accesses ---");

        // 2a. Local Weight Write -> Chip IO Read (Verify Zero Padding)
        $display("Testing Local Weight -> Chip IO (Padding Check)");
        weight_w_v = 1; weight_w_addr = 'd5; weight_w_data = 64'hDEAD_BEEF_CAFE_BABE;
        @(posedge clk); weight_w_v = 0;
        
        chip_io_r_v = 1; chip_io_r_addr = {TAG_W'(0), ADDR_W'('d5)};
        @(posedge clk); #1;
        if (chip_io_r_data === {64'h0, 64'hDEAD_BEEF_CAFE_BABE}) 
            $display("[PASS] Cross Weight Read (Correct Padding)");
        else 
            $display("[FAIL] Cross Weight Read: %h", chip_io_r_data);
        chip_io_r_v = 0;

        // 2b. Chip IO Write -> Local Psum Read
        $display("Testing Chip IO -> Local Psum");
        chip_io_w_v = 1; chip_io_w_addr = {TAG_W'(2), ADDR_W'('d15)};
        chip_io_w_data = 128'h1234_5678_90AB_CDEF_1234_5678_90AB_CDEF;
        @(posedge clk); chip_io_w_v = 0;

        psum_r_v = 1; psum_r_addr = 'd15; @(posedge clk); #1;
        if (psum_r_data === 128'h1234_5678_90AB_CDEF_1234_5678_90AB_CDEF)
            $display("[PASS] Cross Psum Read");
        else
            $display("[FAIL] Cross Psum Read: %h", psum_r_data);
        psum_r_v = 0;

        // ---------------------------------------------------------
        // 3. BOUNDARY CHECKS
        // ---------------------------------------------------------
        $display("\n--- TEST 3: Boundary Checks (Addr 0 and Max) ---");

        // Address 0 (using Weight Bank via Chip IO)
        chip_io_w_v = 1; chip_io_w_addr = {TAG_W'(0), ADDR_W'(0)};
        chip_io_w_data = 128'h1; @(posedge clk); chip_io_w_v = 0;
        
        weight_r_v = 1; weight_r_addr = 0; @(posedge clk); #1;
        if (weight_r_data === 64'h1) $display("[PASS] Boundary Addr 0");
        else $display("[FAIL] Boundary Addr 0: %h", weight_r_data);
        weight_r_v = 0;

        // Max Address (using Psum Bank via Local Port)
        psum_w_v = 1; psum_w_addr = DEPTH-1; psum_w_data = {128{1'b1}};
        @(posedge clk); psum_w_v = 0;
        
        chip_io_r_v = 1; chip_io_r_addr = {TAG_W'(2), ADDR_W'(DEPTH-1)};
        @(posedge clk); #1;
        if (chip_io_r_data === {128{1'b1}}) $display("[PASS] Boundary Addr Max (%0d)", DEPTH-1);
        else $display("[FAIL] Boundary Addr Max: %h", chip_io_r_data);
        chip_io_r_v = 0;

        $display("\nAll requested test cases completed.");
        $finish;
    end

endmodule