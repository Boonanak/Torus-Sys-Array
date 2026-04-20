`timescale 1ns/1ps

module banked_mem_tb;

    initial begin 
        $fsdbDumpfile("waveform.fsdb");
        $fsdbDumpvars("+all");
    end

    // Parameters
    localparam NUM_BANKS = 4;
    localparam CLK_PERIOD = 10;

    // Interface Signals
    logic clk;
    logic reset;
    mem_pkg::r_req read_req  [NUM_BANKS];
    mem_pkg::r_rsp read_rsp  [NUM_BANKS];
    mem_pkg::w_req write_req [NUM_BANKS];
    mem_pkg::w_rsp write_rsp [NUM_BANKS];

    // Instantiate DUT
    banked_mem #(
        .NUM_BANKS(NUM_BANKS)
    ) dut (
        .clk_i(clk),
        .reset(reset),
        .read_request(read_req),
        .read_response(read_rsp),
        .write_request(write_req),
        .write_response(write_rsp)
    );

    // Clock Generation
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Helper task to clear requests
    task clear_reqs();
        for (int i = 0; i < NUM_BANKS; i++) begin
            read_req[i]  = '0;
            write_req[i] = '0;
        end
    endtask
    
    logic [8:0] MATRIX_BASE_ADDR = 10'h1F0; 
    initial begin
        // --- Initialization ---
        reset = 1;
        clear_reqs();
        repeat (2) @(posedge clk);
        reset = 0;
        @(posedge clk);
        // --- 1. HAPPY CASE: Parallel Writes to Different Banks ---
        // Each port writes to its own bank (Port 0 -> Bank 0, Port 1 -> Bank 1, etc.)
        for (int i = 0; i < NUM_BANKS; i++) begin
            write_req[i].valid = 1'b1;
            write_req[i].wren  = 2'b11; // Write both segments [cite: 52]
            write_req[i].addr.fields.bank = i[1:0];
            write_req[i].addr.fields.block_idx = 3'h1;
            write_req[i].data = (64'hAAAA_AAAA_AAAA_AAAA << (i*8)) | i; 
        end
        @(posedge clk);
        clear_reqs();

        // --- 2. HAPPY CASE: Parallel Reads from Different Banks ---
        for (int i = 0; i < NUM_BANKS; i++) begin
            read_req[i].valid = 1'b1;
            read_req[i].addr.fields.bank = i[1:0];
            read_req[i].addr.fields.block_idx = 3'h1;
        end
        #1;
        // Verify Write Responses
        for (int i = 0; i < NUM_BANKS; i++) begin
            if (write_rsp[i].valid !== 1'b1) $error("Happy Case Write: Port %0d failed", i);
        end
        @(posedge clk); // Cycle where data returns from partition_mem [cite: 45]
        
        // --- 3. BANK CONFLICT CASE: Multiple Ports vs One Bank ---
        // Port 0, 1, and 2 all try to read from Bank 3 simultaneously
        read_req[0].valid = 1'b1; read_req[0].addr.fields.bank = 2'd3;
        read_req[1].valid = 1'b1; read_req[1].addr.fields.bank = 2'd3;
        read_req[2].valid = 1'b1; read_req[2].addr.fields.bank = 2'd3;

        #1;

        for (int i = 0; i < NUM_BANKS; i++) begin
            if (read_rsp[i].valid !== 1'b1) $error("Happy Case Read: Port %0d invalid", i);
            $display("Port %0d Read Data: %h", i, read_rsp[i].data);
        end

        @(posedge clk);
        clear_reqs();
        
        #1;
        if (read_rsp[0].valid !== 1'b1) $error("Conflict: Port 0 should have won bank access");
        if (read_rsp[1].valid !== 1'b0) $error("Conflict: Port 1 should have failed (bank busy)");
        if (read_rsp[2].valid !== 1'b0) $error("Conflict: Port 2 should have failed (bank busy)");
        
        repeat (2) @(posedge clk);

        // --- 4. DATA MASKING (partition_mem test) ---
        // Write only to segment 1 (top half) of Bank 0
        write_req[0].valid = 1'b1;
        write_req[0].wren  = 2'b10; // Only top vector [cite: 43]
        write_req[0].addr.fields.bank = 2'd0;
        write_req[0].data = {64'hDEAD_BEEF_CAFE_BABE, 64'h0}; 
        @(posedge clk);
        clear_reqs();
        
        // Read back to ensure only half changed
        read_req[0].valid = 1'b1;
        read_req[0].addr.fields.bank = 2'd0;
        @(posedge clk);
        clear_reqs();
        @(posedge clk);
        
        $display("Masked Read Result: %h", read_rsp[0].data);
        // Expecting top 64 bits to be DEAD...BABE and bottom 64 bits to be from previous write
        @(posedge clk);
        clear_reqs();
        @(posedge clk);

        // --- 5. READ-ONLY PROTECTION TEST ---
        $display("Testing Write Protection on Hard-Coded Rows...");
        
        // Attempt to overwrite the first row of the hard-coded matrix
        write_req[0].valid = 1'b1;
        write_req[0].wren  = 2'b11;
        write_req[0].addr.fields.bank = 2'd3;
        write_req[0].addr.fields.block_idx = 3'b111;
        write_req[0].addr.fields.seg_sel = 1'b1;
        write_req[0].data = 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
        
        @(posedge clk);
        clear_reqs();
        @(posedge clk);

        // Read back the same address to verify the original hard-coded value is still there
        read_req[0].valid = 1'b1;
        read_req[0].addr.fields.bank = 2'd3;
        read_req[0].addr.fields.block_idx = 3'b111;
        read_req[0].addr.fields.seg_sel = 1'b1;

        @(posedge clk);
        clear_reqs();
        @(posedge clk);
        #1;

        if (read_rsp[0].data == 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF) begin
            $warning("Security Alert: Hard-coded matrix was successfully overwritten!");
        end else begin
            $display("Success: Hard-coded matrix is read-only. Data: %h", read_rsp[0].data);
        end


        $display("Simulation Finished.");
        $finish;
    end

endmodule