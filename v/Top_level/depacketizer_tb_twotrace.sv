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

  logic dut_v_lo, dut_v_r;
  logic [31:0] dut_data_lo, dut_data_r;
  logic dut_ready_lo, dut_ready_r;

  logic tr_v_lo;
  logic [129:0] tr_data_lo;
  logic tr_ready_lo, tr_ready_r;

  //logic [31:0] rom_addr_li;
  logic [31:0] rom_addr_send_li; // this was an interesting note. Claude suggested separating these addresses. Let's see if it works
  logic [31:0] rom_addr_recv_li; // new address for recv
  logic [133:0] rom_data_lo_send;
  logic [35:0]  rom_data_lo_recv;

  logic tr_yumi_li, dut_yumi_li;
  logic tr_yumi_send, tr_yumi_recv;

    // / 4 bit trace command / 2 bit packet size / 128 bit packet /
    depacketizer_send_trace_rom #(.width_p(134),.addr_width_p(32))
    ROM_BPS_send
        (.addr_i( rom_addr_send_li ) // send address
        ,.data_o( rom_data_lo_send )
        );

    bsg_fsb_node_trace_replay #(.ring_width_p(130)
                                ,.rom_addr_width_p(32) )
    trace_replay_send
        ( .clk_i ( ~clk ) // Trace Replay should run on negative clock edge!
        , .reset_i( reset )
        , .en_i( 1'b1 )

        , .v_i    ( 1'b0 ) // in theory, there should be no valid_i, since send side is not checking any inputs. previously dut_v_r, now 0
        , .data_i ( 0 ) // nothing
        , .ready_o(  ) // nothing

        , .v_o   ( tr_v_lo )
        , .data_o( tr_data_lo )
        , .yumi_i( tr_yumi_send ) // acknowledge send trace replay's output (DUT consumed the packet). previously gated dut_ready_r & tr_v_lo, now gated dut_ready_lo & tr_v_lo

        , .rom_addr_o( rom_addr_send_li ) // new send address
        , .rom_data_i( rom_data_lo_send )

        , .done_o()
        , .error_o()
        );

    // / 4 bit trace command / 32 bit flit /    
    depacketizer_recv_trace_rom #(.width_p(36),.addr_width_p(32))
    ROM_BPS_recv
        (.addr_i( rom_addr_recv_li ) // recv address
        ,.data_o( rom_data_lo_recv )
        );

    bsg_fsb_node_trace_replay #(.ring_width_p(32)
                                ,.rom_addr_width_p(32) )
    trace_replay_recv
        ( .clk_i ( ~clk ) // Trace Replay should run on negative clock edge!
        , .reset_i( reset )
        , .en_i( 1'b1 )

        , .v_i    ( dut_v_r ) // claude was suggesting not gating these? keeping it for now
        , .data_i ( dut_data_r ) //          "                        "
        , .ready_o( tr_ready_lo ) // tr_ready_lo

        , .v_o   (  )
        , .data_o(  )
        , .yumi_i( tr_yumi_recv ) // should be driven by DUT output (did DUT produce a flit that recv accepted). previously, gated dut_ready_r & tr_v_lo, now gated dut_v_lo & tr_ready_lo

        , .rom_addr_o( rom_addr_recv_li ) // new recv address
        , .rom_data_i( rom_data_lo_recv )

        , .done_o()
        , .error_o()
        );

  always_ff @(posedge clk) begin // according to Claude, this negedge sequential block adds 1/2 cycle delay. let's try making it posedge?
    dut_ready_r  <= dut_ready_lo;
    //tr_yumi_li   <= dut_ready_r & tr_v_lo;
    tr_yumi_send <= dut_ready_lo & tr_v_lo;
    tr_yumi_recv <= dut_v_lo & tr_ready_lo;
    dut_v_r      <= dut_v_lo;
    dut_data_r   <= dut_data_lo;
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
        .ready_o ( dut_ready_lo ), // handshake r_o (input side) --> does it accept new packets from send?
        .flit_o ( dut_data_lo ),
        .valid_o ( dut_v_lo ),
        .ready_i ( 1'b1 ) // handshake r_i --> dut_yumi_li? dut_v_lo (not real handshake)? Claude suggests tr_ready_lo, which hasn't worked well in the past but we will try it. IT DIDNT WORK. Now we are trying just 1
    );

  always_ff @(posedge clk) begin // same thing here, posedge (likely should revert)
    dut_yumi_li <= tr_ready_lo & dut_v_lo; // this is just tr_yumi_recv, Claude still suggests putting this into the ready_i port (as it originally was). Let's see if tr_ready_lo even works and then try that
  end

endmodule