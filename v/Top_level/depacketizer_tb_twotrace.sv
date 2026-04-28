`timescale 1ns / 1ps

module depacketizer_tb;

    /* Dump Test Waveform To VPD File */
  initial begin
    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars();
  end

  /* Non-synth clock generator */
  logic clk;
  bsg_nonsynth_clock_gen #(12000) clk_gen_1 (clk);

  /* Non-synth reset generator */
  logic reset;
  bsg_nonsynth_reset_gen #(.num_clocks_p(1),.reset_cycles_lo_p(5),. reset_cycles_hi_p(5))
    reset_gen
      (.clk_i        ( clk )
      ,.async_reset_o( reset )
      );

  logic dut_v_lo, dut_v_r;
  logic [31:0] dut_data_lo, dut_data_r;
  logic dut_ready_lo, dut_ready_r;

  logic tr_v_lo;
  logic [129:0] tr_data_lo;
  logic tr_ready_lo, tr_ready_r;

  logic [31:0] rom_addr_li;
  logic [133:0] rom_data_lo_send;
  logic [35:0]  rom_data_lo_recv;

  logic tr_yumi_li, dut_yumi_li;

    // / 4 bit trace command / 2 bit packet size / 128 bit packet /
    depacketizer_send_trace_rom #(.width_p(134),.addr_width_p(32))
    ROM_BPS_send
        (.addr_i( rom_addr_li )
        ,.data_o( rom_data_lo_send )
        );

    bsg_fsb_node_trace_replay #(.ring_width_p(130)
                                ,.rom_addr_width_p(32) )
    trace_replay_send
        ( .clk_i ( ~clk ) // Trace Replay should run on negative clock edge!
        , .reset_i( reset )
        , .en_i( 1'b1 )

        , .v_i    ( dut_v_r )
        , .data_i (  ) // nothing
        , .ready_o(  ) // nothing

        , .v_o   ( tr_v_lo )
        , .data_o( tr_data_lo )
        , .yumi_i( tr_yumi_li )

        , .rom_addr_o( rom_addr_li )
        , .rom_data_i( rom_data_lo_send )

        , .done_o()
        , .error_o()
        );

    // / 4 bit trace command / 32 bit flit /    
    depacketizer_recv_trace_rom #(.width_p(36),.addr_width_p(32))
    ROM_BPS_recv
        (.addr_i( rom_addr_li )
        ,.data_o( rom_data_lo_recv )
        );

    bsg_fsb_node_trace_replay #(.ring_width_p(32)
                                ,.rom_addr_width_p(32) )
    trace_replay_recv
        ( .clk_i ( ~clk ) // Trace Replay should run on negative clock edge!
        , .reset_i( reset )
        , .en_i( 1'b1 )

        , .v_i    ( dut_v_r )
        , .data_i ( dut_data_r )
        , .ready_o( tr_ready_lo ) // tr_ready_lo

        , .v_o   (  )
        , .data_o(  )
        , .yumi_i( tr_yumi_li )

        , .rom_addr_o(  )
        , .rom_data_i( rom_data_lo_recv )

        , .done_o()
        , .error_o()
        );

  always_ff @(negedge clk) begin
    dut_ready_r <= dut_ready_lo;
    tr_yumi_li  <= dut_ready_r & tr_v_lo;
    dut_v_r     <= dut_v_lo;
    dut_data_r  <= dut_data_lo;
  end


    depacketizer #(
        .packet_width_p(128),
        .flit_width_p(32),
        .fifo_els_p(4)
    ) DUT (
        .clk_i ( clk ),
        .reset_i ( reset ),
        .packet_i ( tr_data_lo[127:0] ),
        .valid_i ( tr_v_lo ),
        .packet_size_i ( tr_data_lo[129:128] ),
        .ready_o ( dut_ready_lo ),
        .flit_o ( dut_data_lo ),
        .valid_o ( dut_v_lo ),
        .ready_i ( dut_yumi_li ) // handshake r_i --> still dut_yumi_li since we are receiving here...
    );

  always_ff @(negedge clk) begin
    dut_yumi_li <= tr_ready_lo & dut_v_lo;
  end

endmodule