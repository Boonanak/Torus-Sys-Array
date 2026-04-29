`timescale 1ns / 1ps

module TwistMesh_tb_twotrace;

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
  bsg_nonsynth_reset_gen #(.num_clocks_p(1), .reset_cycles_lo_p(5), .reset_cycles_hi_p(5))
    reset_gen
      (.clk_i        ( clk )
      ,.async_reset_o( reset )
      );

  logic dut_v_lo, dut_v_r;
  logic [127:0] dut_data_lo, dut_data_r;
  logic dut_ready_lo, dut_ready_r;

  logic tr_v_lo;
  logic [264:0] tr_data_lo;
  logic tr_ready_lo, tr_ready_r;

  logic [31:0] rom_addr_li;
  logic [269:0] rom_data_lo_send;
  logic [131:0]  rom_data_lo_recv;

  logic tr_yumi_li, dut_yumi_li;
  logic tr_yumi_send, tr_yumi_recv; // NEW

  TwistMesh_send_trace_rom #(.width_p(269),.addr_width_p(32))
    ROM_BPS_send
      (.addr_i( rom_addr_li )
      ,.data_o( rom_data_lo_send )
      );

  bsg_fsb_node_trace_replay #(.ring_width_p(265)
                             ,.rom_addr_width_p(32) )
    trace_replay_send
      ( .clk_i ( ~clk ) // Trace Replay should run on negative clock edge!
      , .reset_i( reset )
      , .en_i( 1'b1 )

      , .v_i    (  )
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

  TwistMesh_recv_trace_rom #(.width_p(132),.addr_width_p(32))
    ROM_BPS_recv
      (.addr_i( rom_addr_li )
      ,.data_o( rom_data_lo_recv )
      );

  bsg_fsb_node_trace_replay #(.ring_width_p(128)
                             ,.rom_addr_width_p(32) )
    trace_replay_recv
      ( .clk_i ( ~clk ) // Trace Replay should run on negative clock edge!
      , .reset_i( reset )
      , .en_i( 1'b1 )

      , .v_i    ( dut_v_lo ) // NEW (no longer registered)
      , .data_i ( dut_data_r ) // NEW (no longer registered)
      , .ready_o( tr_ready_lo )

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
    tr_yumi_li  <= '1;
    dut_v_r     <= dut_v_lo;
    dut_data_r  <= dut_data_lo;
  end

    // ================================================================
    // Parameters
    // ================================================================
    localparam N = 8;
    localparam IW = 8;
    localparam WW = 8;
    localparam OW = 16;

    // ================================================================
    // DUT signals
    // ================================================================
    logic signed [WW-1:0]  in_weight  [N-1:0];
    logic                  in_lock    [N-1:0];
    logic signed [IW-1:0]  in_ifmap   [N-1:0];
    logic signed [OW-1:0]  in_psum    [N-1:0];
    logic                  in_propagate;
    logic signed [OW-1:0]  out_psum   [N-1:0];

    assign in_weight = {tr_data_lo[191:184], tr_data_lo[183:176], tr_data_lo[175:168], tr_data_lo[167:160],
                        tr_data_lo[159:152], tr_data_lo[151:144], tr_data_lo[143:136], tr_data_lo[135:128]};
    assign in_lock   = {>>{tr_data_lo[263:256]}};
    assign in_ifmap  = {tr_data_lo[255:248], tr_data_lo[247:240], tr_data_lo[239:232], tr_data_lo[231:224],
                        tr_data_lo[223:216], tr_data_lo[215:208], tr_data_lo[207:200], tr_data_lo[199:192]};
    assign in_psum   = {tr_data_lo[127:112], tr_data_lo[111:96], tr_data_lo[95:80], tr_data_lo[79:64],
                        tr_data_lo[63:48], tr_data_lo[47:32], tr_data_lo[31:16], tr_data_lo[15:0]};
    assign in_propagate = tr_data_lo[264];

    TwistMesh #(
         .N_p            (N)
        ,.INPUT_WIDTH_p  (IW)
        ,.WEIGHT_WIDTH_p (WW)
        ,.OUTPUT_WIDTH_p (OW)
    ) DUT (
         .clk_i          ( clk )
        ,.reset_i        ( reset )
        ,.in_weight_i    ( in_weight )
        ,.in_lock_i      ( in_lock )
        ,.in_ifmap_i     ( in_ifmap )
        ,.in_psum_i      ( in_psum )
        ,.in_propagate_i ( in_propagate )
        ,.in_valid_i     ( tr_v_lo ) // Handshake v_i
        ,.in_last_i      ( tr_ready_lo & dut_v_lo ) // Handshake r_i
        ,.out_psum_o     ( out_psum )
        ,.out_valid_o    ( dut_v_lo ) // Handshake v_o
        ,.out_last_o     ( dut_ready_lo ) // Handshake r_o
    );

    assign dut_data_lo[127:112] = out_psum[7];
    assign dut_data_lo[111:96] = out_psum[6];
    assign dut_data_lo[95:80] = out_psum[5];
    assign dut_data_lo[79:64] = out_psum[4];
    assign dut_data_lo[63:48] = out_psum[3];
    assign dut_data_lo[47:32] = out_psum[2];
    assign dut_data_lo[31:16]  = out_psum[1];
    assign dut_data_lo[15:0]   = out_psum[0];

  always_ff @(negedge clk) begin
    dut_yumi_li <= tr_ready_lo & dut_v_lo;
  end


endmodule