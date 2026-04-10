`timescale 1ns / 1ps

module Pipette_PE_tb;
    
    /* Dump Test Waveform To VPD File */
    initial begin 
        $fsdbDumpfile("waveform.fsdb");
        $fsdbDumpvars("+all");
    end

    /* Non-synth clock generator */
    logic clk;
    bsg_nonsynth_clock_gen #(7500) clk_gen_1 (clk);

    /* Non-synth reset generator */
    logic reset;
    bsg_nonsynth_reset_gen #(.num_clocks_p(1),.reset_cycles_lo_p(5),. reset_cycles_hi_p(5))
        reset_gen
        (.clk_i        ( clk )
        ,.async_reset_o( reset )
        );

    logic dut_v_lo, dut_v_r;
    logic [43:0] dut_data_lo, dut_data_r;
    logic dut_ready_lo, dut_ready_r;

    logic tr_v_lo;
    logic [43:0] tr_data_lo;
    logic tr_ready_lo, tr_ready_r;

    logic [31:0] rom_addr_li;
    logic [47:0] rom_data_lo;

    logic tr_yumi_li, dut_yumi_li;

    bsg_fsb_node_trace_replay #(.ring_width_p(44)
                                ,.rom_addr_width_p(32) )
        trace_replay
        ( .clk_i ( ~clk ) // Trace Replay should run on negative clock edge!
        , .reset_i( reset )
        , .en_i( 1'b1 )

        , .v_i    ( dut_v_r )
        , .data_i ( dut_data_r )
        , .ready_o( tr_ready_lo )

        , .v_o   ( tr_v_lo )
        , .data_o( tr_data_lo )
        , .yumi_i( tr_yumi_li )

        , .rom_addr_o( rom_addr_li )
        , .rom_data_i( rom_data_lo )

        , .done_o()
        , .error_o()
        );

    always_ff @(negedge clk) begin
        dut_ready_r <= dut_ready_lo;
        tr_yumi_li  <= dut_ready_r & tr_v_lo;
        dut_v_r     <= dut_v_lo;
        dut_data_r  <= dut_data_lo;
    end

    // 4 bit tracereplay, 16 bit A, 16 bit PS, 8 bit B, 
    // 4 bits combined for row major, A_en, B_en, ALP 
    Pipette_PE_rom #(.width_p(48),.addr_width_p(32))
        ROM_BPS
        (.addr_i( rom_addr_li )
        ,.data_o( rom_data_lo )
        );

    // input: tr_data_lo { 1 (R), 16 (A), 8 (B), 16 (PS), 3 (control)} 
    // output: dut_data_lo with same format, unnecessary signals 0
    Pipette_PE DUT
        (.clk_i  ( clk )
        ,.reset( reset )

        ,.row_major_in ( tr_data_lo[43] )
        ,.enable_A  ( tr_data_lo[42] )
        ,.enable_B  ( tr_data_lo[41] )
        ,.active_lock_pulse_in ( tr_data_lo[40] )
        ,.active_lock_pulse_out( dut_data_lo[40] )

        ,.A_in ( tr_data_lo[39:24] )
        ,.B_in ( tr_data_lo[23:16] )
        ,.PS_in( tr_data_lo[15:0] )

        ,.A_out ( dut_data_lo[39:24] )
        ,.B_out ( dut_data_lo[23:16] )
        ,.PS_out( dut_data_lo[15:0] )
        );

    // no handshake logic. all ready/valid signal is 1 for PE
    assign dut_ready_lo = '1;
    assign dut_v_lo = '1;
    
    // assign 0 on unused bits
    assign dut_data_lo[43:41] = '0;

    always_ff @(negedge clk) begin
        dut_yumi_li <= tr_ready_lo & dut_v_lo;
    end
    
endmodule