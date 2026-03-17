`timescale 1ns / 1ps

module Top_level_tb_twotrace;

    /* Dump Test Waveform To VPD File */
  initial begin
    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars("+all");
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
  logic [63:0] dut_data_lo, dut_data_r;
  logic dut_ready_lo, dut_ready_r;

  logic tr_v_lo;
  logic [63:0] tr_data_lo;
  logic tr_ready_lo, tr_ready_r;

  logic [31:0] rom_addr_li;
  logic [67:0] rom_data_lo_send, rom_data_lo_recv;

  logic tr_yumi_li, dut_yumi_li;

  bsg_fsb_node_trace_replay #(.ring_width_p(64)
                             ,.rom_addr_width_p(32) )
    trace_replay_recv
      ( .clk_i ( ~clk ) // Trace Replay should run on negative clock edge!
      , .reset_i( reset )
      , .en_i( 1'b1 )

      , .v_i    ( dut_v_r )
      , .data_i ( dut_data_r )
      , .ready_o( tr_ready_lo )

      , .v_o   (  )
      , .data_o(  )
      , .yumi_i( tr_yumi_li )

      , .rom_addr_o(  )
      , .rom_data_i( rom_data_lo_recv )

      , .done_o()
      , .error_o()
      );

  bsg_fsb_node_trace_replay #(.ring_width_p(64)
                             ,.rom_addr_width_p(32) )
    trace_replay_send
      ( .clk_i ( ~clk ) // Trace Replay should run on negative clock edge!
      , .reset_i( reset )
      , .en_i( 1'b1 )

      , .v_i    ( dut_v_r )
      , .data_i (  )
      , .ready_o(  )

      , .v_o   ( tr_v_lo )
      , .data_o( tr_data_lo )
      , .yumi_i( tr_yumi_li )

      , .rom_addr_o( rom_addr_li )
      , .rom_data_i( rom_data_lo_send )

      , .done_o()
      , .error_o()
      );

  always_ff @(negedge clk) begin
    dut_ready_r <= dut_ready_lo;
    tr_yumi_li  <= '1;
    dut_v_r     <= dut_v_lo;
    dut_data_r  <= dut_data_lo;
  end

  // / 1 bit load_B / 8 bits A / 16 bits B_PS / 4 bits for trace replay
  sys_array_send_trace_rom #(.width_p(68),.addr_width_p(32))
    ROM_BPS_send
      (.addr_i( rom_addr_li )
      ,.data_o( rom_data_lo_send )
      );

  sys_array_recv_trace_rom #(.width_p(68),.addr_width_p(32))
    ROM_BPS_recv
      (.addr_i( rom_addr_li )
      ,.data_o( rom_data_lo_recv )
      );

  logic [15:0] ps_out_data [3:0];
  logic [15:0] A_out_data [3:0];
  logic [7:0] transposer_data_in [3:0];

  assign transposer_data_in[3] = tr_data_lo[31:24];
  assign transposer_data_in[2] = tr_data_lo[23:16];
  assign transposer_data_in[1] = tr_data_lo[15:8];
  assign transposer_data_in[0] = tr_data_lo[7:0];

  // use this for sim-syn and sim-par

  // `ifdef SYNTHESIS
    // sys_array DUT
    //   (.clk_i       ( clk )
    //   ,.reset     ( reset )
    //   ,.load_B    ( tr_data_lo[63] )
    //   ,.row_major ( tr_data_lo[62] )

    //   ,.\transposer_data[0] ( transposer_data_in[0] )
    //   ,.\transposer_data[1] ( transposer_data_in[1] )
    //   ,.\transposer_data[2] ( transposer_data_in[2] )
    //   ,.\transposer_data[3] ( transposer_data_in[3] )      

    //   ,.\A_out_right[0]     ()
    //   ,.\A_out_right[1]     ()
    //   ,.\A_out_right[2]     ()
    //   ,.\A_out_right[3]     ()

    //   ,.\PS_out_right[0]    ( ps_out_data[0] )
    //   ,.\PS_out_right[1]    ( ps_out_data[1] )
    //   ,.\PS_out_right[2]    ( ps_out_data[2] )
    //   ,.\PS_out_right[3]    ( ps_out_data[3] )

    //   ,.transposer_valid_in  ( tr_v_lo )
    //   ,.transposer_ready_out ( dut_ready_lo )

    //   ,.output_buffer_ready_in  ( tr_ready_lo & dut_v_lo )
    //   ,.output_buffer_valid_out ( dut_v_lo )
    //   );
  
  // `else
  // use this for sim-rtl 

    Top_level DUT
      (.clk_i     ( clk )
      ,.reset_i   ( reset )

      ,.v_i ( tr_v_lo )
      ,.data_i ( tr_data_lo[31:0] )
      ,.ready_o ( dut_ready_lo )
      ,.in_major_mode ( tr_data_lo[63] )
      ,.in_load_weight ( tr_data_lo[62] )

      ,.v_o ( dut_v_lo )
      ,.data_o ( dut_data_lo[63:0] )
      ,.ready_i ( dut_yumi_li )
      );
  // `endif

  always_ff @(negedge clk) begin
    dut_yumi_li <= tr_ready_lo & dut_v_lo;
  end


endmodule