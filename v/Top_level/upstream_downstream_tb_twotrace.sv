`timescale 1ns / 1ps

module upstream_downstream_tb_twotrace;

  /* Dump Test Waveform To VPD File */
  initial begin
  $fsdbDumpfile("waveform.fsdb");
  $fsdbDumpvars("+all");
  end

  // ============================================================
  // Clocks
  // ============================================================
 
  // Testbench clock — drives trace replays (negedge) and io_clk derivation
  logic clk;
  bsg_nonsynth_clock_gen #(12000) clk_gen_tb (clk);
 
  // Core clock — drives DUT core domain (same period as tb clock)
  logic core_clk;
  bsg_nonsynth_clock_gen #(12000) clk_gen_core (core_clk);
 
  // IO master clock — dedicated high-speed clock for bsg_link upstream IO domain
  // Must be provided separately; use 2x core speed (6000ps = half of 12000ps period)
  logic io_master_clk;
  bsg_nonsynth_clock_gen #(6000) clk_gen_io_master (io_master_clk);

  // ============================================================
  // Testbench Reset (for trace replays only)
  // ============================================================
  logic tb_reset;
  bsg_nonsynth_reset_gen #(
    .num_clocks_p    (1),
    .reset_cycles_lo_p(1),
    .reset_cycles_hi_p(2)
  ) reset_gen_tb (
    .clk_i        ( clk      ),
    .async_reset_o( tb_reset )
  );
 
  // ============================================================
  // Async reset for the bsg_link reset state machine
  // This is the raw async reset input — held high long enough
  // for the state machine to see it, then released.
  // The state machine itself handles all downstream sequencing.
  // ============================================================
  logic async_reset;
  bsg_nonsynth_reset_gen #(
    .num_clocks_p    (1),
    .reset_cycles_lo_p(4),
    .reset_cycles_hi_p(12)
  ) reset_gen_async (
    .clk_i        ( core_clk   ),
    .async_reset_o( async_reset )
  );

  // ============================================================
  // bsg_link Reset State Machine
  // Faithfully reproduced from bsg_guts.v
  // ============================================================
 
  localparam max_val_lp = 32;
  localparam CNT_WIDTH  = 6; // enough to count to 32
 
  typedef enum logic [2:0] {S1, S2, S3, S4, S5, S6, S7, S8} reset_state_e;
  reset_state_e reset_state_r, reset_state_n;
 
  logic [CNT_WIDTH-1:0] counter_r, counter_n;
 
  // Registered reset outputs (all clocked on core_clk)
  logic core_clk_link_reset_r,        core_clk_link_reset_n;
  logic core_io_upstream_link_reset_r, core_io_upstream_link_reset_n;
  logic core_io_downstream_link_reset_r, core_io_downstream_link_reset_n;
 
  // Combinational outputs of the state machine
  logic async_token_reset;
  logic calib_done;
 
  // Synchronize async_reset into core_clk domain
  logic sync_reset_lo;
  bsg_sync_sync #(.width_p(1)) bss_reset (
    .oclk_i      ( core_clk    ),
    .iclk_data_i ( async_reset ),
    .oclk_data_o ( sync_reset_lo )
  );
 
  // Counter register
  always_ff @(posedge core_clk) begin
    if (sync_reset_lo) counter_r <= '0;
    else               counter_r <= counter_n;
  end
 
  // Reset state register
  always_ff @(posedge core_clk) begin
    if (sync_reset_lo) reset_state_r <= S1;
    else               reset_state_r <= reset_state_n;
  end
 
  // core_clk_link_reset register — starts HIGH (in reset)
  always_ff @(posedge core_clk) begin
    if (sync_reset_lo) core_clk_link_reset_r <= 1'b1;
    else               core_clk_link_reset_r <= core_clk_link_reset_n;
  end
 
  // upstream io link reset register — starts HIGH (in reset)
  always_ff @(posedge core_clk) begin
    if (sync_reset_lo) core_io_upstream_link_reset_r <= 1'b1;
    else               core_io_upstream_link_reset_r <= core_io_upstream_link_reset_n;
  end
 
  // downstream io link reset register — starts LOW (NOT in reset)
  always_ff @(posedge core_clk) begin
    if (sync_reset_lo) core_io_downstream_link_reset_r <= 1'b0;
    else               core_io_downstream_link_reset_r <= core_io_downstream_link_reset_n;
  end
 
  // State machine combinational logic
  always_comb begin
    // Defaults: hold state, hold resets, increment counter
    reset_state_n                    = reset_state_r;
    async_token_reset                = 1'b0;
    core_clk_link_reset_n            = core_clk_link_reset_r;
    core_io_upstream_link_reset_n    = core_io_upstream_link_reset_r;
    core_io_downstream_link_reset_n  = core_io_downstream_link_reset_r;
    counter_n                        = counter_r + 1'b1;
    calib_done                       = 1'b0;
 
    case (reset_state_r)
 
      S1: begin // Wait for initial settling
        if (counter_r == max_val_lp) begin
          reset_state_n = S2;
          counter_n     = '0;
        end
      end
 
      S2: begin // Assert async token reset
        async_token_reset = 1'b1;
        if (counter_r == max_val_lp) begin
          reset_state_n = S3;
          counter_n     = '0;
        end
      end
 
      S3: begin // Deassert async token reset, let it settle
        async_token_reset = 1'b0;
        if (counter_r == max_val_lp) begin
          reset_state_n = S4;
          counter_n     = '0;
        end
      end
 
      S4: begin // Release upstream IO link reset (was HIGH, now go LOW)
        core_io_upstream_link_reset_n = 1'b0;
        if (counter_r == max_val_lp) begin
          reset_state_n = S5;
          counter_n     = '0;
        end
      end
 
      S5: begin // Assert downstream IO link reset (was LOW, pulse HIGH)
        core_io_downstream_link_reset_n = 1'b1;
        if (counter_r == max_val_lp) begin
          reset_state_n = S6;
          counter_n     = '0;
        end
      end
 
      S6: begin // Release downstream IO link reset (back to LOW)
        core_io_downstream_link_reset_n = 1'b0;
        if (counter_r == max_val_lp) begin
          reset_state_n = S7;
          counter_n     = '0;
        end
      end
 
      S7: begin // Release core clock link reset (was HIGH, now go LOW)
        core_clk_link_reset_n = 1'b0;
        if (counter_r == max_val_lp) begin
          reset_state_n = S8;
          counter_n     = '0;
        end
      end
 
      S8: begin // Calibration complete — system is live
        calib_done = 1'b1;
        counter_n  = counter_r; // stop counting
      end
 
      default: reset_state_n = S1;
 
    endcase
  end
 
  // ============================================================
  // Synchronize IO domain resets across clock domain boundaries
  // (matching bsg_guts.v exactly)
  // ============================================================
 
  // Upstream io reset: core_clk -> io_master_clk domain
  logic io_upstream_link_reset;
  bsg_launch_sync_sync #(.width_p(1)) link_upstream_reset_sync (
    .iclk_i      ( core_clk                      ),
    .iclk_reset_i( 1'b0                           ),
    .oclk_i      ( io_master_clk                  ),  // io_master_clk domain
    .iclk_data_i ( core_io_upstream_link_reset_r  ),
    .iclk_data_o (                                ),
    .oclk_data_o ( io_upstream_link_reset         )
  );
 
  // Downstream io reset: core_clk -> forwarded io_clk domain
  // NOTE: io_clk_o (forwarded from upstream) is used here,
  // matching how bsg_guts uses io_clk_tline_i[0]
  logic io_downstream_link_reset;
  logic io_clk_o; // declared here, driven by upstream wrapper below
 
  bsg_launch_sync_sync #(.width_p(1)) link_downstream_reset_sync (
    .iclk_i      ( core_clk                        ),
    .iclk_reset_i( 1'b0                             ),
    .oclk_i      ( io_clk_o                         ),  // forwarded clock domain
    .iclk_data_i ( core_io_downstream_link_reset_r  ),
    .iclk_data_o (                                  ),
    .oclk_data_o ( io_downstream_link_reset          )
  );


  logic dut_v_lo;
  logic [31:0] dut_data_lo;
  logic dut_ready_lo;

  logic tr_v_lo;
  logic [130:0] tr_data_lo;
  logic tr_ready_lo;

  logic [31:0] rom_addr_li;
  logic [134:0] rom_data_lo_send;
  logic [35:0]  rom_data_lo_recv;

  // / 4 bit trace command / 2 bit packet size / 128 bit packet /
  upstream_downstream_send_trace_rom #(.width_p(135),.addr_width_p(32))
  ROM_BPS_send
    (.addr_i( rom_addr_li ) 
    ,.data_o( rom_data_lo_send )
    );

  bsg_fsb_node_trace_replay #(.ring_width_p(131)
                              ,.rom_addr_width_p(32) )
  trace_replay_send
    ( .clk_i ( ~clk ) // Trace Replay should run on negative clock edge!
    , .reset_i( tb_reset )
    , .en_i( calib_done )

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
  upstream_downstream_recv_trace_rom #(.width_p(36),.addr_width_p(32))
  ROM_BPS_recv
    (.addr_i( rom_addr_li )
    ,.data_o( rom_data_lo_recv )
    );

  bsg_fsb_node_trace_replay #(.ring_width_p(32)
                              ,.rom_addr_width_p(32) )
  trace_replay_recv
    ( .clk_i ( ~clk ) // Trace Replay should run on negative clock edge!
    , .reset_i( tb_reset )
    , .en_i( calib_done )

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

  logic token_clk;
  logic token_clk_from_downstream;
  logic io_valid;
  logic io_clk_o;
  logic [0:0][16:0] io_data;
  logic parity_error;

  logic token_clk_init;
  logic [4:0] token_init_count;
  logic token_init_done;

  // During reset sequence, pulse token_clk at io_master_clk rate
  // to pre-load credits into upstream's counter
  always_ff @(posedge io_master_clk) begin
      if (tb_reset) begin
          token_init_count = 0;
          token_clk_init = 0;
      end else if (!calib_done && token_init_count < 5'd31) begin
          token_init_count <= token_init_count + 1;
          token_clk_init   <= ~token_clk_init;
      end
  end

  // After calib_done, switch to real token return path
  assign token_clk = calib_done ? token_clk_from_downstream : token_clk_init;

  upstream_wrapper #(
    .packet_width_p(128),
    .flit_width_p(32),
    .fifo_els_p(4),
    .channel_width_p(17),
    .num_channels_p(1)
  ) DUT_upstream (
    .core_clk_i ( core_clk ),
    .core_reset_i ( core_clk_link_reset_r ),     // driven by state machine   
    .packet_i ( tr_data_lo[127:0] ),        // input data from send trace replay
    .valid_i ( tr_v_lo ),                   // handshake v_i --> comes from send side v_o
    .packet_size_i( tr_data_lo[130:128] ),  // input data from send trace replay
    .ready_o( dut_ready_lo ),               // handshake r_o --> goes to send side r_i

    .io_clk_i ( io_master_clk ),
    .io_link_reset_i ( io_upstream_link_reset ), // driven by state machine
    .async_token_reset_i ( async_token_reset ),  // driven by state machine
    .io_clk_r_o ( io_clk_o ),               // output clk to downstream
    .io_data_r_o ( io_data ),               // output data to downstream
    .io_valid_r_o ( io_valid ),             // handshake v_o --> gpes to downstream v_i
    .token_clk_i ( token_clk )              // essentially handshake r_i, comes from downstream r_o (previously token_clk, temporarily 1)
  );

  downstream_wrapper #(
    .flit_width_p(32),
    .channel_width_p(17),
    .num_channels_p(1)
  ) DUT_downstream (
    .core_clk_i ( core_clk ),
    .core_reset_i ( core_clk_link_reset_r ),       // driven by state machine
    .flit_o ( dut_data_lo ),          // output data to recv trace replay
    .valid_o ( dut_v_lo ),                  // handshake v_o --> goes to receive side v_i
    .ready_i ( 1'b1 ),               // handshake r_i --> comes from receive side r_o (tr_ready_lo)
    .parity_error_o ( parity_error ),       // output data to recv trace replay

    .io_clk_i ( io_clk_o ),                 // input io clock should come from upstream
    .io_link_reset_i ( io_downstream_link_reset ), // driven by state machine
    .io_data_i ( io_data ),                 // input data should come from upstream
    .io_valid_i ( io_valid ),               // handshake v_i --> comes from upstream v_o
    .token_clk_o ( token_clk_from_downstream )              // essentially handshake r_o, will go to upstream r_i
  );

endmodule