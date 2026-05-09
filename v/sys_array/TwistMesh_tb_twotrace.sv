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

  // ================================================================
  // Parameters
  // ================================================================
  localparam N = 8;
  localparam IW = 8;
  localparam WW = 8;
  // localparam OW = 16;
  localparam OW = 32; // T2SA-MESH: int32 psum
  localparam OUTPUT_DATA_SIZE = N * OW; // 256
  localparam INPUT_DATA_SIZE = 1 + N + N*IW + N*WW + N*OW; // 393
  localparam IFMAP_START = INPUT_DATA_SIZE-2-N; // 383
  localparam WEIGHT_START = IFMAP_START-8*IW; // 319
  localparam PSUM_START = OUTPUT_DATA_SIZE - 1; // 255

  logic dut_v_lo, dut_v_r;
  logic [OUTPUT_DATA_SIZE-1:0] dut_data_lo, dut_data_r;
  logic dut_ready_lo, dut_ready_r;

  logic tr_v_lo;
  logic [INPUT_DATA_SIZE-1:0] tr_data_lo;
  logic tr_ready_lo, tr_ready_r;

  logic [31:0] rom_addr_li;
  logic [INPUT_DATA_SIZE+3:0] rom_data_lo_send;
  logic [OUTPUT_DATA_SIZE+3:0]  rom_data_lo_recv;

  logic tr_yumi_li, dut_yumi_li;
  logic tr_yumi_send, tr_yumi_recv; // NEW

  TwistMesh_send_trace_rom #(.width_p(INPUT_DATA_SIZE+4),.addr_width_p(32))
    ROM_BPS_send
      (.addr_i( rom_addr_li )
      ,.data_o( rom_data_lo_send )
      );

  bsg_fsb_node_trace_replay #(.ring_width_p(INPUT_DATA_SIZE)
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

  TwistMesh_recv_trace_rom #(.width_p(OUTPUT_DATA_SIZE+4),.addr_width_p(32))
    ROM_BPS_recv
      (.addr_i( rom_addr_li )
      ,.data_o( rom_data_lo_recv )
      );

  bsg_fsb_node_trace_replay #(.ring_width_p(OUTPUT_DATA_SIZE)
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
    // tr_yumi_li   <= dut_ready_r & tr_v_lo;
    tr_yumi_li  <= '1;
    dut_v_r     <= dut_v_lo;
    dut_data_r  <= dut_data_lo;
  end



    // ================================================================
    // DUT signals
    // ================================================================
    logic signed [WW-1:0]  in_weight  [N-1:0];
    logic                  in_lock    [N-1:0];
    logic signed [IW-1:0]  in_ifmap   [N-1:0];
    logic signed [OW-1:0]  in_psum    [N-1:0];
    logic                  in_propagate;
    logic signed [OW-1:0]  out_psum   [N-1:0];

    assign in_weight = {tr_data_lo[WEIGHT_START:WEIGHT_START-WW+1], tr_data_lo[WEIGHT_START-WW:WEIGHT_START-2*WW+1], tr_data_lo[WEIGHT_START-2*WW:WEIGHT_START-3*WW+1], tr_data_lo[WEIGHT_START-3*WW:WEIGHT_START-4*WW+1],
                        tr_data_lo[WEIGHT_START-4*WW:WEIGHT_START-5*WW+1], tr_data_lo[WEIGHT_START-5*WW:WEIGHT_START-6*WW+1], tr_data_lo[WEIGHT_START-6*WW:WEIGHT_START-7*WW+1], tr_data_lo[WEIGHT_START-7*WW:WEIGHT_START-8*WW+1]};
    assign in_lock   = {>>{tr_data_lo[INPUT_DATA_SIZE-2:INPUT_DATA_SIZE-1-N]}};
    assign in_ifmap  = {tr_data_lo[IFMAP_START:IFMAP_START-IW+1], tr_data_lo[IFMAP_START-IW:IFMAP_START-2*IW+1], tr_data_lo[IFMAP_START-2*IW:IFMAP_START-3*IW+1], tr_data_lo[IFMAP_START-3*IW:IFMAP_START-4*IW+1],
                        tr_data_lo[IFMAP_START-4*IW:IFMAP_START-5*IW+1], tr_data_lo[IFMAP_START-5*IW:IFMAP_START-6*IW+1], tr_data_lo[IFMAP_START-6*IW:IFMAP_START-7*IW+1], tr_data_lo[IFMAP_START-7*IW:IFMAP_START-8*IW+1]};
    assign in_psum   = {tr_data_lo[PSUM_START:PSUM_START-OW+1], tr_data_lo[PSUM_START-OW:PSUM_START-2*OW+1], tr_data_lo[PSUM_START-2*OW:PSUM_START-3*OW+1], tr_data_lo[PSUM_START-3*OW:PSUM_START-4*OW+1],
                        tr_data_lo[PSUM_START-4*OW:PSUM_START-5*OW+1], tr_data_lo[PSUM_START-5*OW:PSUM_START-6*OW+1], tr_data_lo[PSUM_START-6*OW:PSUM_START-7*OW+1], tr_data_lo[PSUM_START-7*OW:PSUM_START-8*OW+1]};
    assign in_propagate = tr_data_lo[INPUT_DATA_SIZE-1];

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

    assign dut_data_lo[PSUM_START:PSUM_START-OW+1]        = out_psum[7];
    assign dut_data_lo[PSUM_START-OW:PSUM_START-2*OW+1]   = out_psum[6];
    assign dut_data_lo[PSUM_START-2*OW:PSUM_START-3*OW+1] = out_psum[5];
    assign dut_data_lo[PSUM_START-3*OW:PSUM_START-4*OW+1] = out_psum[4];
    assign dut_data_lo[PSUM_START-4*OW:PSUM_START-5*OW+1] = out_psum[3];
    assign dut_data_lo[PSUM_START-5*OW:PSUM_START-6*OW+1] = out_psum[2];
    assign dut_data_lo[PSUM_START-6*OW:PSUM_START-7*OW+1] = out_psum[1];
    assign dut_data_lo[PSUM_START-7*OW:PSUM_START-8*OW+1] = out_psum[0];

  always_ff @(negedge clk) begin
    dut_yumi_li <= tr_ready_lo & dut_v_lo;
  end


endmodule