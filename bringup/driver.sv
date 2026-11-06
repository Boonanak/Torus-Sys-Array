module driver (
    // from the board
    input  logic        clk_i,        // CLOCK_50 or a PLL output
    input  logic        rst_i,        // user reset, active high (invert KEY at the top)
    input  logic        run_i,        // start the trace (a switch)

    // interface with chip
    output logic core_clk,
    output logic hard_reset,
    
    // bsg_link downstream data receive
    output logic [16:0] rx_data,
    output logic rx_clk,
    input  logic rx_token,
    output logic rx_valid,
    
    // bsg_link upstream data transmit
    input  logic [16:0] tx_data,
    input  logic tx_clk,
    output logic tx_token,
    input  logic tx_valid,

    output logic scan_en,
    output logic scan_in,
    input  logic scan_out,

    // status to the board
    output logic        trace_ready_o, // confirmation of the reset sequence finishing
    output logic        done_o,        // both traces finished
    output logic        error_o,       // any mismatch (sticky)
    output logic        parity_err_o,
    output logic [31:0] send_addr_o,   // for HEX displays
    output logic [31:0] recv_addr_o,

    // streaming output, one pulse per flit received from the chip
    output logic        out_valid_o,
    output logic [31:0] out_data_o
);

    localparam int FLIT_WIDTH    = 36;
    localparam int CHANNEL_WIDTH = 18;

    // ----- Clocks + global control -----
    logic dn_io_clk;          // FPGA's TX I/O master clock; bsg_link_oddr_phy ÷2 → 50 MHz forwarded to PAD[8]

    // ----- Reset stages (mirrors bsg_link reference tb staging) -----
    logic fpga_core_reset;
    logic fpga_tx_io_link_reset;
    logic fpga_tx_async_token_reset;
    logic fpga_rx_io_link_reset;
    logic fpga_rx_io_link_reset_sync;  

    // ----- bsg_link wires shared with chip's PAD bus -----
    logic                       fpga_to_asic_clk;
    logic                       fpga_to_asic_valid;
    logic [CHANNEL_WIDTH-1:0]   fpga_to_asic_data;
    logic                       fpga_to_asic_token;   // FPGA RX -> chip TX token_clk
    logic                       asic_to_fpga_token;   // chip RX -> FPGA TX token
    logic                       asic_to_fpga_clk;
    logic                       asic_to_fpga_valid;
    logic [CHANNEL_WIDTH-1:0]   asic_to_fpga_data;

    assign rx_data = fpga_to_asic_data[16:0];
    assign rx_clk = fpga_to_asic_clk;
    assign asic_to_fpga_token = rx_token;
    assign rx_valid = fpga_to_asic_valid;
    assign asic_to_fpga_data = tx_data;
    assign asic_to_fpga_clk = tx_clk;
    assign tx_token = fpga_to_asic_token;
    assign asic_to_fpga_valid = tx_valid;
    assign scan_en = 1'b0;   // tie off until you want scan control
    assign scan_in = 1'b0;


    // ----- FPGA-side bsg_link instances (peers to chip's wrapper) -----
    logic [FLIT_WIDTH-1:0] fpga_tx_data;
    logic                  fpga_tx_valid;
    logic                  fpga_tx_valid_r;
    logic                  fpga_tx_ready;
    logic [FLIT_WIDTH-1:0] fpga_rx_data;
    logic                  fpga_rx_valid;
    logic                  fpga_rx_yumi;

    logic [31:0] fpga_tx_data_real; // FROM FPGA
    logic [31:0] fpga_rx_data_real; // FROM CHIP

    // PARITY BITS SENT BY FPGA
    logic fpga_tx_parity_low, fpga_tx_parity_high;
    parity_generator #(.WIDTH_p(16)) pg_low (
        .bits_i(fpga_tx_data_real[15:0]),
        .parity_o(fpga_tx_parity_low)
    );
    parity_generator #(.WIDTH_p(16)) pg_high (
        .bits_i(fpga_tx_data_real[31:16]),
        .parity_o(fpga_tx_parity_high)
    );

    logic fpga_rx_parity_low, fpga_rx_parity_high;
    logic fpga_rx_ok_low, fpga_rx_ok_high;
    logic fpga_rx_parity_error;
    parity_checker #(.WIDTH_p(16)) check_low (
        .bits_i(fpga_rx_data[15:0]),
        .parity_i(fpga_rx_parity_low),
        .is_parity_o(fpga_rx_ok_low)
    );
    parity_checker #(.WIDTH_p(16)) check_high (
        .bits_i(fpga_rx_data[33:18]),
        .parity_i(fpga_rx_parity_high),
        .is_parity_o(fpga_rx_ok_high)
    );
    assign fpga_rx_parity_error = fpga_rx_valid && (!fpga_rx_ok_low || !fpga_rx_ok_high);

    assign fpga_tx_data = {1'b0, fpga_tx_parity_high, fpga_tx_data_real[31:16], 1'b0, fpga_tx_parity_low, fpga_tx_data_real[15:0]};
    assign fpga_rx_data_real[31:16] = fpga_rx_data[33:18];
    assign fpga_rx_parity_high      = fpga_rx_data[34];
    assign fpga_rx_data_real[15:0]  = fpga_rx_data[15:0];
    assign fpga_rx_parity_low       = fpga_rx_data[16];
    

    bsg_link_wrapper #(
        .FLIT_WIDTH    (36),
        .CHANNEL_WIDTH (18)
    ) u_bsg_link_wrapper (
        .core_clk_i                (core_clk),
        .reset_i                   (fpga_core_reset),
        .io_master_clk_i           (dn_io_clk),
        .upstream_io_link_reset_i  (fpga_tx_io_link_reset),
        .async_token_reset_i       (fpga_tx_async_token_reset),
        .token_clk_i               (asic_to_fpga_token),
        .downstream_io_link_reset_i(fpga_rx_io_link_reset_sync),
        .downstream_io_clk_i       (asic_to_fpga_clk),
        .downstream_io_data_i      (asic_to_fpga_data), // this is currently 18 bits
        .downstream_io_valid_i     (asic_to_fpga_valid),
        .upstream_io_clk_r_o       (fpga_to_asic_clk),
        .upstream_io_data_r_o      (fpga_to_asic_data), // this is currently 18 bits
        .upstream_io_valid_r_o     (fpga_to_asic_valid),
        .downstream_core_token_r_o (fpga_to_asic_token),
        .rx_data_o                 (fpga_rx_data), // this is currently 36 bits
        .rx_valid_o                (fpga_rx_valid),
        .rx_yumi_i                 (fpga_rx_yumi),
        .tx_data_i                 (fpga_tx_data), // this is currently 36 bits
        .tx_valid_i                (fpga_tx_valid_r),
        .tx_ready_o                (fpga_tx_ready)
    );

    bsg_sync_sync #(.width_p(1)) fpga_rx_reset_sync (
        .oclk_i      (asic_to_fpga_clk),
        .iclk_data_i (fpga_rx_io_link_reset),
        .oclk_data_o (fpga_rx_io_link_reset_sync)
    );

    // assign fpga_rx_yumi = fpga_rx_valid;

    // Track FPGA-side RX from chip
    logic [31:0] fpga_last_rx_data;
    integer                fpga_rx_count;
    always_ff @(posedge core_clk) begin
        if (fpga_core_reset) begin
            fpga_rx_count     <= 0;
            fpga_last_rx_data <= '0;
        end else if (fpga_rx_valid && fpga_rx_yumi) begin
            fpga_rx_count     <= fpga_rx_count + 1;
            fpga_last_rx_data <= fpga_rx_data_real;
        end
    end


    // CREATION OF CLOCKS
    assign core_clk = clk_i;  // 50 MHz if clk_i is CLOCK_50
    assign dn_io_clk = clk_i; // 50 MHz if clk_i is CLOCK_50

    // // ----- Clock and reset generation -----
    // logic [31:0] clkdiv;

    // // FPGA clk
    // // assign clk = SW[8] ? KEY[3] : clkdiv[20]; // 50 MHz
    // assign core_clk = clkdiv[2]; 
    // assign dn_io_clk = clkdiv[2];  
    // always_ff @(posedge clk_i) begin
    //     clkdiv <= rst_i ? 32'b0 : clkdiv + 1;
    // end


    /* THIS IS THE OLD RESET SEQUENCER */
    // // STRAY TRACE SIGNAL (bc order matters)
    logic trace_enable;


    // //     // Reset bring-up order for our chip:
    // //     //  1) Pulse FPGA TX async_token_reset (chip RX side will see tokens
    // //     //     once data starts flowing).
    // //     //  2) Release FPGA TX I/O link reset (FPGA TX starts driving the
    // //     //     chip's RX-side data clock).
    // //     //  3) Release chip's hard_reset. The chip's internal reset
    // //     //     sequencer takes ~32 core_clks to bring its bsg_link out of
    // //     //     reset (async_token pulse, io_link, then core).
    // //     //  4) After the chip is running, release FPGA RX I/O link reset
    // //     //     so the FPGA RX side sees a valid up_clk from the chip.
    // //     //  5) Release FPGA core reset.
    

    // // Test sequence hardware-based
    // enum logic [3:0] {init = 4'h0, fpga_tx_async_assert = 4'h1, fpga_tx_async_deassert = 4'h2,
    //                    fpga_tx_io_deassert = 4'h4, hard_rst_deassert = 4'h5, fpga_rx_io_deassert = 4'h6,
    //                    core_reset_deassert = 4'h7, start_main = 4'h8
    //                  } reset_seq;

    // logic [10:0] wait_amount;
    // logic wait_done;


    // always_ff @(posedge clk_i) begin
    //     if (rst_i) begin
    //         wait_amount      <= 'b0;
	// 		wait_done        <= 1'b0;
    //     end else if (wait_done) begin
    //         case (reset_seq)
    //             init                  : wait_amount               <= 11'h8;
    //             fpga_tx_async_assert  : wait_amount               <= 11'h2;
    //             fpga_tx_async_deassert: wait_amount               <= 11'h8;
    //             fpga_tx_io_deassert   : wait_amount               <= 11'h8;
    //             hard_rst_deassert     : wait_amount               <= 11'd64;  
    //             fpga_rx_io_deassert   : wait_amount               <= 11'h8;
    //             core_reset_deassert   : wait_amount               <= 11'd200; 
    //         endcase
    //     end else if (wait_amount == 1'b0) begin
    //         wait_done <= 1'b1;
    //     end else begin
    //         wait_amount <= wait_amount - 1'b1;
	// 		wait_done <= 1'b0;
    //     end

    // end


    // always_ff @(posedge clk_i) begin 
    //     if (rst_i) begin
    //         reset_seq <= init;
    //     end

    //     if (wait_done) begin
    //         case (reset_seq)
    //             init: begin
    //                 hard_reset                <= 1'b1;
    //                 fpga_core_reset           <= 1'b1;
    //                 fpga_tx_io_link_reset     <= 1'b1;
    //                 fpga_tx_async_token_reset <= 1'b0;
    //                 fpga_rx_io_link_reset     <= 1'b1;
    //                 trace_enable              <= 1'b0;
    //                 reset_seq                 <= fpga_tx_async_assert;
    //             end

    //             fpga_tx_async_assert: begin
    //                 reset_seq                 <= fpga_tx_async_deassert;
    //                 fpga_tx_async_token_reset <= 1'b1;
    //             end

    //             fpga_tx_async_deassert: begin
    //                 reset_seq                 <= fpga_tx_io_deassert;
    //                 fpga_tx_async_token_reset <= 1'b0;
    //             end

    //             fpga_tx_io_deassert: begin
    //                 reset_seq                 <= hard_rst_deassert;
    //                 fpga_tx_io_link_reset     <= 1'b0;
    //             end

    //             hard_rst_deassert: begin
    //                 reset_seq                 <= fpga_rx_io_deassert;
    //                 hard_reset                <= 1'b0;   
    //             end

    //             fpga_rx_io_deassert: begin
    //                 reset_seq                 <= core_reset_deassert;
    //                 fpga_rx_io_link_reset     <= 1'b0;
    //             end

    //             core_reset_deassert: begin
    //                 reset_seq                 <= start_main;
    //                 fpga_core_reset           <= 1'b0;    
    //             end

    //             start_main: begin
    //                 trace_enable              <= 1'b1;
    //             end

    //             default: reset_seq <= init;
    //         endcase
    //     end
    // end

    /* THIS IS THE NEW RESET SEQUENCER EQUIVALENT TO THAT OF DUT */
    // // ----- Internal reset sequencer for bsg_link init protocol -----
    // // bsg_async_credit_counter requires:
    // //   1. Assert r_reset (= io_link_reset, on io_clk domain).
    // //   2. While r_reset asserted, pulse w_reset (= async_token_reset)
    // //      0 -> 1 -> 0 at least once.
    // //   3. Wait >=4 r_clock posedges before deasserting r_reset.
    // //   4. Deassert r_reset.
    // //
    // // Tying every link reset to hard_reset would violate that ordering, so
    // // the chip generates the staged reset internally from a single counter
    // // that starts running once hard_reset deasserts.
    // wire hard_reset_sync;
    // reg [7:0] reset_cnt = 8'd0;
    // always @(posedge clk_i) begin
    //     if (rst_i)              reset_cnt <= 8'd0;
    //     else if (reset_cnt < 6'd200)       reset_cnt <= reset_cnt + 6'd1;
    // end

    // assign hard_reset = (reset_cnt < 8'd64);

    // // async_token_reset: 0 normally, pulsed 1 during counts 2..4 after
    // // hard_reset_sync deasserts. Held 0 during reset (matches bsg ref tb).
    // assign fpga_tx_async_token_reset = (reset_cnt >= 8'd2) && (reset_cnt <  8'd5);

    // // io_link_resets: held high while reset is asserted, then for
    // // ~16 more core_clk cycles after the async_token_reset pulse.
    // // upstream (TX) releases first so the other chip's downstream FIFO
    // // write-side sees clock edges while its own reset is still asserted,
    // // satisfying the BSG sync-reset requirement for bsg_circular_ptr.
    // // downstream (RX) holds 12 extra core_clk cycles after upstream releases.
    // // UP_CLK is 25 MHz (= core_clk/2), so 12 core cycles = 6 UP_CLK cycles of
    // // margin, ensuring the bsg_async_ptr_gray sync-reset fires 4+ times before
    // // the RX FIFO write-side reset deasserts.  Stays clear of core_link_reset
    // // at cnt=32.
    // assign fpga_tx_io_link_reset = (reset_cnt < 8'd16);
    // assign fpga_rx_io_link_reset = (reset_cnt < 8'd100);

    // // core link reset: released last (~32 cycles after hard_reset_sync).
    // assign fpga_core_reset = (reset_cnt < 8'd200);

    /* THIS IS THE RESET SEQUENCER WRITTEN BY CLAUDE */
    typedef enum logic [2:0] {
         S_TOKEN_ASSERT
        ,S_TOKEN_DEASSERT
        ,S_TX_IO_RELEASE
        ,S_HARD_RELEASE
        ,S_RX_IO_RELEASE
        ,S_CORE_RELEASE
        ,S_RUN
    } state_e;
 
    state_e      state;
    logic [10:0] wait_cnt;
    logic        running;
 
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state                     <= S_TOKEN_ASSERT;
            wait_cnt                  <= 11'd8;
            hard_reset                <= 1'b1;
            fpga_core_reset           <= 1'b1;
            fpga_tx_io_link_reset     <= 1'b1;
            fpga_tx_async_token_reset <= 1'b0;
            fpga_rx_io_link_reset     <= 1'b1;
            running                   <= 1'b0;
        end else if (wait_cnt != 11'd0) begin
            wait_cnt <= wait_cnt - 11'd1;
        end else begin
            case (state)
                S_TOKEN_ASSERT: begin
                    fpga_tx_async_token_reset <= 1'b1;
                    wait_cnt <= 11'd2;
                    state    <= S_TOKEN_DEASSERT;
                end
                S_TOKEN_DEASSERT: begin
                    fpga_tx_async_token_reset <= 1'b0;
                    wait_cnt <= 11'd8;
                    state    <= S_TX_IO_RELEASE;
                end
                S_TX_IO_RELEASE: begin
                    fpga_tx_io_link_reset <= 1'b0;
                    wait_cnt <= 11'd8;
                    state    <= S_HARD_RELEASE;
                end
                S_HARD_RELEASE: begin
                    hard_reset <= 1'b0;
                    wait_cnt <= 11'd64;
                    state    <= S_RX_IO_RELEASE;
                end
                S_RX_IO_RELEASE: begin
                    fpga_rx_io_link_reset <= 1'b0;
                    wait_cnt <= 11'd8;
                    state    <= S_CORE_RELEASE;
                end
                S_CORE_RELEASE: begin
                    fpga_core_reset <= 1'b0;
                    wait_cnt <= 11'd200;
                    state    <= S_RUN;
                end
                S_RUN: begin
                    running <= 1'b1;
                end
                default: state <= S_TOKEN_ASSERT;
            endcase
        end
    end
 
    assign trace_enable = running & run_i;
    assign trace_ready_o = running;

    // TRACE REPLAY

    // --- Trace Replay Signals ---

    // Addressing
    logic [31:0] rom_addr_send, rom_addr_recv;
    logic [31+4:0] rom_data_send;
    logic [31+4:0] rom_data_recv;
    logic done_send, done_recv;
    logic error_send, error_recv;

    // Send side
    logic [31:0] tr_data_lo;
    logic        tr_v_lo;
    logic        tr_yumi_li;

    // Recv side
    logic tr_ready_lo, tr_ready_r;
    logic dut_v_lo, dut_v_r;
    logic[31:0] dut_data_lo, dut_data_r;

    // --- Send Trace Replay (Drives 32 bit flit) ---
    trace_replay #(
        .ring_width_p(32), .rom_addr_width_p(32)
        ,.rom_len_p(53)                 // number of lines in the send ROM (0..52)
        ,.timeout_cycles_p(12_500_000)  // ~1 s at 12.5 MHz; use a small value in simulation
        ,.drain_after_error_p(1)
    ) tracer_send (
         .clk_i  (~core_clk) // Run replay on opposite edge for stability
        ,.reset_i(hard_reset)
        ,.en_i   (trace_enable)
        ,.halt_i (error_recv)
        
        ,.v_i    (1'b0)
        ,.data_i ('0)
        ,.ready_o()

        ,.v_o    (tr_v_lo)
        ,.data_o (tr_data_lo)
        ,.yumi_i (tr_yumi_li)

        ,.rom_addr_o(rom_addr_send)
        ,.rom_data_i(rom_data_send)
        ,.done_o    (done_send)
        ,.error_o   (error_send)
        ,.mismatch_o(), .timeout_o(), .overrun_o(), .err_got_o(), .err_exp_o()
    );

    // // Mapping Trace Replay to Top Level Input
    // assign in_flit        = tr_data_lo;
    // assign in_flit_v      = tr_v_lo;
    // assign in_flit_par_ok = 1'b1; // Assuming parity is always good for functional test
    // assign tr_yumi_li     = in_flit_ready & in_flit_v;



    always_ff @(negedge core_clk) begin 
        tr_ready_r <= tr_ready_lo && dut_v_lo; // fpga_rx_yumi, previously link_out_yumi_i
        dut_v_r <= dut_v_lo;
        dut_data_r <= dut_data_lo;
        fpga_tx_valid_r <= fpga_tx_valid;
    end

    assign tr_yumi_li = fpga_tx_ready && fpga_tx_valid_r;

    // --- Receive Trace Replay (Validates link_out) ---
    trace_replay #(
         .ring_width_p(32), .rom_addr_width_p(32)
        ,.rom_len_p(150)                // lines in the recv ROM (0..149)
        ,.timeout_cycles_p(12_500_000)
        ,.drain_after_error_p(1)
    ) tracer_recv (
         .clk_i  (~core_clk)
        ,.reset_i(hard_reset)
        ,.en_i   (trace_enable & run_i)
        ,.halt_i (error_send)

        ,.v_i    (dut_v_r)
        ,.data_i (dut_data_r)
        ,.ready_o(tr_ready_lo) // This ready effectively acts as 'yumi' for the DUT

        ,.v_o    ()
        ,.data_o ()
        ,.yumi_i (1'b0)

        ,.rom_addr_o(rom_addr_recv)
        ,.rom_data_i(rom_data_recv)
        ,.done_o    (done_recv)
        ,.error_o   (error_recv)
        ,.mismatch_o(), .timeout_o(), .overrun_o(), .err_got_o(), .err_exp_o()
    );

    // --- Trace ROMs ---

    benchmark5_send_trace_rom #(.width_p(32+4), .addr_width_p(32)) 
        ROM_send (.addr_i(rom_addr_send), .data_o(rom_data_send));
    benchmark5_recv_trace_rom #(.width_p(32+4), .addr_width_p(32))
        ROM_recv (.addr_i(rom_addr_recv), .data_o(rom_data_recv));

    // HERE WE WILL CONNECT TRACE REPLAY SIGNALS TO ACTUAL TESTBENCH SIGNALS
    assign fpga_tx_data_real = tr_data_lo;
    assign fpga_tx_valid = tr_v_lo;
    //assign tr_yumi_li = fpga_tx_ready;
    assign fpga_rx_yumi = tr_ready_lo && dut_v_r;
    assign dut_data_lo = fpga_rx_data_real;
    assign dut_v_lo = fpga_rx_valid;


    assign done_o       = done_send | done_recv;
    assign error_o      = error_send | error_recv;
    assign parity_err_o = fpga_rx_parity_error;
    assign send_addr_o  = rom_addr_send;
    assign recv_addr_o  = rom_addr_recv;
    assign out_valid_o  = fpga_rx_valid & fpga_rx_yumi;
    assign out_data_o   = fpga_rx_data_real;

endmodule
