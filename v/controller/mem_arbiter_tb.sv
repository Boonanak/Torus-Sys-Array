`timescale 1ns/1ps

module mem_arbiter_tb;

    // --- Parameters ---
    localparam int DIM = 4;
    localparam int NUM_MATRICES = 2; 
    localparam int ADDR_W = 3; 
    localparam int IFM_W = DIM * 8;   // 32-bit
    localparam int WGT_W = DIM * 8;   // 32-bit
    localparam int PSM_W = DIM * 16;  // 64-bit

    // --- Signals ---
    logic clk = 0;
    logic reset = 0;
    always #5 clk = ~clk;

    // EX Interface Inputs
    logic ex_active;
    logic ex_ifm_r_v, ex_wgt_r_v, ex_psm_r_v, ex_psm_w_v, ex_ifm_w_v;
    logic [ADDR_W-1:0] ex_ifm_r_addr, ex_wgt_r_addr, ex_psm_r_addr, ex_psm_w_addr, ex_ifm_w_addr;
    logic [IFM_W-1:0]  ex_ifm_w_data;
    logic [PSM_W-1:0]  ex_psm_w_data;
    
    // External Interface Inputs
    logic wr_v_ext, rd_v_ext;
    logic [ADDR_W-1:0] addr_ext;
    logic [PSM_W-1:0]  wr_data_ext;
    scratchpad_pkg::sp_bank_id_e wr_bank_ext, rd_bank_ext;

    // Bank Feedback (Mocking memory bank outputs to the Arbiter)
    logic [IFM_W-1:0] ifm_r_data_i;
    logic [WGT_W-1:0] wgt_r_data_i;
    logic [PSM_W-1:0] psm_r_data_i;

    // DUT Outputs
    logic [IFM_W-1:0] ex_ifm_r_data_o, ex_wgt_r_data_o;
    logic [PSM_W-1:0] ex_psm_r_data_o, rd_data_ext_o;
    logic ifm_w_v_o, ifm_r_v_o, wgt_w_v_o, wgt_r_v_o, psm_w_v_o, psm_r_v_o;
    logic [ADDR_W-1:0] ifm_w_addr_o, ifm_r_addr_o, wgt_w_addr_o, wgt_r_addr_o, psm_w_addr_o, psm_r_addr_o;
    logic [IFM_W-1:0] ifm_w_data_o;
    logic [WGT_W-1:0] wgt_w_data_o;
    logic [PSM_W-1:0] psm_w_data_o;
    logic mem_conflict_o;

    // --- DUT Instantiation ---
    mem_arbiter #( 
        .DIM_p(DIM), 
        .NUM_MATRICES_p(NUM_MATRICES) 
    ) dut (
        .clk_i(clk), .reset_i(reset),
        .ex_active_i(ex_active),
        // EX Inputs
        .ex_ifm_r_v_i(ex_ifm_r_v), .ex_ifm_r_addr_i(ex_ifm_r_addr), .ex_ifm_r_data_o(ex_ifm_r_data_o),
        .ex_wgt_r_v_i(ex_wgt_r_v), .ex_wgt_r_addr_i(ex_wgt_r_addr), .ex_wgt_r_data_o(ex_wgt_r_data_o),
        .ex_psm_r_v_i(ex_psm_r_v), .ex_psm_r_addr_i(ex_psm_r_addr), .ex_psm_r_data_o(ex_psm_r_data_o),
        .ex_psm_w_v_i(ex_psm_w_v), .ex_psm_w_addr_i(ex_psm_w_addr), .ex_psm_w_data_i(ex_psm_w_data),
        .ex_ifm_w_v_i(ex_ifm_w_v), .ex_ifm_w_addr_i(ex_ifm_w_addr), .ex_ifm_w_data_i(ex_ifm_w_data),
        // External
        .wr_v_i(wr_v_ext), .wr_addr_i(addr_ext), .wr_data_i(wr_data_ext), .wr_bank_i(wr_bank_ext),
        .rd_v_i(rd_v_ext), .rd_addr_i(addr_ext), .rd_bank_i(rd_bank_ext), .rd_data_o(rd_data_ext_o),
        // Bank Side
        .ifm_w_v_o(ifm_w_v_o), .ifm_w_addr_o(ifm_w_addr_o), .ifm_w_data_o(ifm_w_data_o),
        .ifm_r_v_o(ifm_r_v_o), .ifm_r_addr_o(ifm_r_addr_o), .ifm_r_data_i(ifm_r_data_i),
        .wgt_w_v_o(wgt_w_v_o), .wgt_w_addr_o(wgt_w_addr_o), .wgt_w_data_o(wgt_w_data_o),
        .wgt_r_v_o(wgt_r_v_o), .wgt_r_addr_o(wgt_r_addr_o), .wgt_r_data_i(wgt_r_data_i),
        .psm_w_v_o(psm_w_v_o), .psm_w_addr_o(psm_w_addr_o), .psm_w_data_o(psm_w_data_o),
        .psm_r_v_o(psm_r_v_o), .psm_r_addr_o(psm_r_addr_o), .psm_r_data_i(psm_r_data_i),
        .mem_conflict_o(mem_conflict_o)
    );

    // --- Helper Task: Clear All Inputs ---
    task clear_inputs();
        ex_active      = 0;
        ex_ifm_r_v     = 0; ex_wgt_r_v  = 0; ex_psm_r_v  = 0; 
        ex_psm_w_v     = 0; ex_ifm_w_v  = 0;
        ex_ifm_r_addr  = 0; ex_wgt_r_addr = 0; ex_psm_r_addr = 0; 
        ex_psm_w_addr  = 0; ex_ifm_w_addr = 0;
        ex_ifm_w_data  = 0; ex_psm_w_data = 0;
        
        wr_v_ext       = 0; rd_v_ext    = 0;
        addr_ext       = 0; wr_data_ext = 0;
        wr_bank_ext    = scratchpad_pkg::BANK_IFMAP; 
        rd_bank_ext    = scratchpad_pkg::BANK_IFMAP;

        ifm_r_data_i   = 0; wgt_r_data_i = 0; psm_r_data_i = 0;
    endtask

    initial begin
        // 1. Zero-init everything immediately
        clear_inputs();
        reset = 1;
        repeat(2) @(posedge clk);
        reset = 0;

        // --- TEST 1: External Store to IFM (Mirror Check) ---
        $display("TC1: External Store...");
        clear_inputs(); 
        wr_v_ext    = 1;
        wr_bank_ext = scratchpad_pkg::BANK_IFMAP;
        addr_ext    = 3'b101;
        wr_data_ext = 64'hBAAD_F00D_CAFE_BABE; // Lower 32 bits should go to IFM/WGT
        #1;
        assert(ifm_w_v_o && wgt_w_v_o) else $error("Mirroring failed");
        assert(ifm_w_data_o == 32'hCAFE_BABE) else $error("Data mismatch");

        // --- TEST 2: EX Priority Dominance ---
        $display("TC2: EX Priority Dominance...");
        clear_inputs();
        ex_active     = 1;
        ex_psm_w_v    = 1;
        ex_psm_w_addr = 3'b010;
        ex_psm_w_data = 64'h1122334455667788;
        
        wr_v_ext      = 1; // Collision
        addr_ext      = 3'b111;
        #1;
        assert(psm_w_v_o == 1 && psm_w_addr_o == 3'b010) else $error("EX did not win address mux");
        assert(mem_conflict_o == 1) else $error("Conflict signal missing");

        // --- TEST 3: External Read Path (Mux Check) ---
        $display("TC3: External Read Path...");
        clear_inputs();
        rd_v_ext      = 1;
        rd_bank_ext   = scratchpad_pkg::BANK_PSUM;
        addr_ext      = 3'b100;
        psm_r_data_i  = 64'hDEADD00D_FEEDFACE; // Mock memory output
        #1;
        assert(rd_data_ext_o == 64'hDEADD00D_FEEDFACE) else $error("Read mux failed");
        $finish;
    end

endmodule