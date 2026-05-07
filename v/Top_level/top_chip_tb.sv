`timescale 1ns / 1ps

module top_chip_tb;

    import ctrl_pkg::*;
    import scratchpad_pkg::*;
    import PE_pkg::*;

    // Waveform Dumping
    initial begin 
        $fsdbDumpfile("waveform.fsdb");
        $fsdbDumpvars("+all");
    end

    // --- Parameters ---
    parameter int DIM_p           = 8;
    parameter int NUM_MATRICES_p  = 4;
    parameter int CMDQ_DEPTH_p    = 8;
    
    // Trace Widths based on top_chip IO
    localparam int SEND_WIDTH_lp = 32; // in_flit width
    localparam int RECV_WIDTH_lp = 32; // link_out_data_o width

    logic clk_i;
    bsg_nonsynth_clock_gen #(.cycle_time_p(10000)) clk_gen (clk_i);

    logic reset_i;
    bsg_nonsynth_reset_gen #(.num_clocks_p(1), .reset_cycles_lo_p(5), .reset_cycles_hi_p(5))
        reset_gen (.clk_i(clk_i), .async_reset_o(reset_i));

    // --- DUT Signals ---
    logic [31:0] in_flit;
    logic        in_flit_v;
    logic        in_flit_par_ok;
    logic        in_flit_ready;

    logic        link_out_v_o;
    logic [31:0] link_out_data_o;
    logic        link_out_parity_o;
    logic        link_out_yumi_i;

    // --- Trace Replay Signals ---
    logic [31:0] tr_data_lo;
    logic        tr_v_lo;
    logic        tr_yumi_li;

    logic [31:0] rom_addr_send, rom_addr_recv;
    logic [SEND_WIDTH_lp+3:0] rom_data_send;
    logic [RECV_WIDTH_lp+3:0] rom_data_recv;
    logic done_send, done_recv;

    // --- DUT Instantiation ---
    top_chip #(
         .DIM_p(DIM_p)
        ,.CMDQ_DEPTH_p(CMDQ_DEPTH_p)
    ) dut (
         .clk_i   (clk_i)
        ,.reset_i (reset_i)

        // Input Path
        ,.in_flit        (in_flit)
        ,.in_flit_v      (in_flit_v)
        ,.in_flit_par_ok (in_flit_par_ok)
        ,.in_flit_ready  (in_flit_ready)

        // Output Path
        ,.link_out_v_o      (link_out_v_o)
        ,.link_out_data_o   (link_out_data_o)
        //,.link_out_parity_o (link_out_parity_o)
        ,.link_out_yumi_i   (link_out_yumi_i)
    );

    // --- Send Trace Replay (Feeds in_flit) ---
    bsg_fsb_node_trace_replay #(
        .ring_width_p(SEND_WIDTH_lp)
       ,.rom_addr_width_p(32)
    ) tracer_send (
         .clk_i  (~clk_i) // Run replay on opposite edge for stability
        ,.reset_i(reset_i)
        ,.en_i   (1'b1)
        
        ,.v_i    (1'b0)
        ,.data_i ('0)
        ,.ready_o()

        ,.v_o    (tr_v_lo)
        ,.data_o (tr_data_lo)
        ,.yumi_i (tr_yumi_li)

        ,.rom_addr_o(rom_addr_send)
        ,.rom_data_i(rom_data_send)
        ,.done_o    (done_send)
        ,.error_o   ()
    );

    // Mapping Trace Replay to Top Level Input
    assign in_flit        = tr_data_lo;
    assign in_flit_v      = tr_v_lo;
    assign in_flit_par_ok = 1'b1; // Assuming parity is always good for functional test
    assign tr_yumi_li     = in_flit_ready & in_flit_v;

    // --- Receive Trace Replay (Validates link_out) ---
    bsg_fsb_node_trace_replay #(
        .ring_width_p(RECV_WIDTH_lp)
       ,.rom_addr_width_p(32)
    ) tracer_recv (
         .clk_i  (~clk_i)
        ,.reset_i(reset_i)
        ,.en_i   (1'b1)

        ,.v_i    (link_out_v_o)
        ,.data_i (link_out_data_o)
        ,.ready_o(link_out_yumi_i) // This ready effectively acts as 'yumi' for the DUT

        ,.v_o    ()
        ,.data_o ()
        ,.yumi_i (1'b0)

        ,.rom_addr_o(rom_addr_recv)
        ,.rom_data_i(rom_data_recv)
        ,.done_o    (done_recv)
        ,.error_o   ()
    );

    // --- Trace ROMs ---

    // top_chip_send_trace_rom #(.width_p(SEND_WIDTH_lp+4), .addr_width_p(32)) 
    //     ROM_send (.addr_i(rom_addr_send), .data_o(rom_data_send));
    // top_chip_recv_trace_rom #(.width_p(RECV_WIDTH_lp+4), .addr_width_p(32))
    //     ROM_recv (.addr_i(rom_addr_recv), .data_o(rom_data_recv));

    benchmark1_send_trace_rom #(.width_p(SEND_WIDTH_lp+4), .addr_width_p(32)) 
        ROM_send (.addr_i(rom_addr_send), .data_o(rom_data_send));

    benchmark1_recv_trace_rom #(.width_p(RECV_WIDTH_lp+4), .addr_width_p(32))
        ROM_recv (.addr_i(rom_addr_recv), .data_o(rom_data_recv));
    // Finish logic
    always @(posedge clk_i) begin
        if (done_send && done_recv) begin
            $display("Testbench Completed Successfully.");
            $finish;
        end
    end

endmodule