`timescale 1ns / 1ps

module depacketizer_tb_twotrace;

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

  logic dut_v_lo;
  logic [31:0] dut_data_lo;

  logic tr_v_lo;
  logic [130:0] tr_data_lo;
  logic tr_ready_lo;

  logic [31:0] rom_addr_li;
  logic [134:0] rom_data_lo_send;
  logic [35:0]  rom_data_lo_recv;

  // / 4 bit trace command / 2 bit packet size / 128 bit packet /
  depacketizer_send_trace_rom #(.width_p(135),.addr_width_p(32))
  ROM_BPS_send
    (.addr_i( rom_addr_li ) 
    ,.data_o( rom_data_lo_send )
    );

  bsg_fsb_node_trace_replay #(.ring_width_p(131)
                              ,.rom_addr_width_p(32) )
  trace_replay_send
    ( .clk_i ( ~clk ) // Trace Replay should run on negative clock edge!
    , .reset_i( reset )
    , .en_i( 1'b1 )

    , .v_i    (  )          // handshake v_i --> empty; no (clocked) input to send side
    , .data_i (  )          // data_i        --> empty; no (clocked) input to send side
    , .ready_o(  )          // handshake r_o --> empty; no (clocked) input to send side

    , .v_o   ( tr_v_lo )    // handshake v_o --> goes to DUT v_i
    , .data_o( tr_data_lo ) // data_o        --> goes to DUT data_i
    , .yumi_i( 1'b1 )       // handshake r_i --> set to 1 in this testbench (assuming faulty r_o signal from DUT)

    , .rom_addr_o( rom_addr_li ) // new send address
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

    , .v_i    ( dut_v_lo )     // handshake v_i --> comes from DUT v_o
    , .data_i ( dut_data_lo )  // data_i        --> comes from DUT data_o
    , .ready_o( tr_ready_lo )  // handshake r_o --> goes to DUT r_i

    , .v_o   (  )              // handshake v_o --> empty; no output from recv side
    , .data_o(  )              // data_o        --> empty; no output from recv side
    , .yumi_i(  )              // handshake r_i --> empty; no output from recv side

    , .rom_addr_o(  ) 
    , .rom_data_i( rom_data_lo_recv )

    , .done_o()
    , .error_o()
    );

  depacketizer #(
    .packet_width_p(128),
    .flit_width_p(32),
    .fifo_els_p(4)
  ) DUT (
    .clk_i ( clk ),
    .reset_i ( reset ),
    .packet_i ( tr_data_lo[127:0] ),
    .valid_i ( tr_v_lo ),         // handshake v_i --> comes from send side v_o
    .packet_size_i ( tr_data_lo[130:128] ),
    .ready_o (  ),                // handshake r_o --> currently not accurate so 1 is sent into send side r_i
    .flit_o ( dut_data_lo ),
    .valid_o ( dut_v_lo ),        // handshake v_o --> goes to receive side v_i
    .ready_i ( tr_ready_lo )      // handshake r_i --> comes from receive side r_o
  );

endmodule