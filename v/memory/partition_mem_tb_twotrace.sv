`timescale 1ns / 1ps

module partition_mem_tb_twotrace;

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
  logic [143:0] tr_data_lo;
  logic tr_ready_lo, tr_ready_r;

  logic [31:0] rom_addr_li;
  logic [147:0] rom_data_lo_send
  logic [131:0]  rom_data_lo_recv;

  logic tr_yumi_li, dut_yumi_li;

  partition_mem_send_trace_rom #(.width_p(148),.addr_width_p(32))
    ROM_BPS_send
      (.addr_i( rom_addr_li )
      ,.data_o( rom_data_lo_send )
      );

  bsg_fsb_node_trace_replay #(.ring_width_p(144)
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

  partition_mem_recv_trace_rom #(.width_p(132),.addr_width_p(32))
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

  always_ff @(negedge clk) begin
    dut_ready_r <= dut_ready_lo;
    tr_yumi_li  <= '1;
    dut_v_r     <= dut_v_lo;
    dut_data_r  <= dut_data_lo;
  end

    partition_mem #(
        .VECTOR_WIDTH_p     (64),
        .VECTORS_PER_ROW_p  (2),
        .NUM_VECTORS_p      (64),
        .HARD_CODE_IDENTITY (0),
        .HARD_CODE_ZERO     (0)
    ) (
        .clk_i        ( clk ),
        .reset        ( reset ),
        .read_addr_i  ( tr_data_lo[134:128] ),
        .write_addr_i ( tr_data_lo[141:135] ),
        .wren_i       ( tr_data_lo[143:142] ),
        .write_data_i ( tr_data_lo[127:0] ),
        .read_data_o  ( dut_data_lo[127:0] )
    );

  always_ff @(negedge clk) begin
    dut_yumi_li <= tr_ready_lo & dut_v_lo;
  end


endmodule