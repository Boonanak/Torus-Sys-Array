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
    input  logic scan_out

    // status to the board
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

    // ----- Clock and reset generation -----
    logic [31:0] clkdiv;

    // FPGA clk
    // assign clk = SW[8] ? KEY[3] : clkdiv[20]; // 50 MHz
    assign core_clk = clkdiv[2]; 
    assign dn_io_clk = clkdiv[2];  
    always_ff @(posedge CLOCK_50) begin
        clkdiv <= rst_i ? 32'b0 : clkdiv + 1;
    end



    // STRAY TRACE SIGNAL (bc order matters)
    logic trace_enable;


    //     // Reset bring-up order for our chip:
    //     //  1) Pulse FPGA TX async_token_reset (chip RX side will see tokens
    //     //     once data starts flowing).
    //     //  2) Release FPGA TX I/O link reset (FPGA TX starts driving the
    //     //     chip's RX-side data clock).
    //     //  3) Release chip's hard_reset. The chip's internal reset
    //     //     sequencer takes ~32 core_clks to bring its bsg_link out of
    //     //     reset (async_token pulse, io_link, then core).
    //     //  4) After the chip is running, release FPGA RX I/O link reset
    //     //     so the FPGA RX side sees a valid up_clk from the chip.
    //     //  5) Release FPGA core reset.
    //     repeat (8) @(posedge core_clk);
    //     fpga_tx_async_token_reset = 1'b1;
    //     repeat (2) @(posedge core_clk);
    //     fpga_tx_async_token_reset = 1'b0;

    //     repeat (8) @(posedge dn_io_clk);
    //     fpga_tx_io_link_reset = 1'b0;

    //     // Release chip's hard_reset; wait for its internal sequencer to
    //     // finish (>=32 core_clks).
    //     repeat (8) @(posedge core_clk);
    //     hard_reset = 1'b0;
    //     repeat (64) @(posedge core_clk);

    //     // Now the chip is driving up_clk; safe to bring up FPGA RX.
    //     fpga_rx_io_link_reset = 1'b0;
    //     repeat (8) @(posedge core_clk);
    //     fpga_core_reset = 1'b0;

    //     // Let chip exit reset and start emitting status words
    //     repeat (200) @(posedge core_clk);
    //     trace_enable = 1'b1;
    //     $display("post-reset: rx_count=%0d, last_status=%h",
    //              fpga_rx_count, fpga_last_rx_data);

    //     // Test 1: bsg_link config write (10 words)
    //     $display("Test 1: send 10 bsg_link config words to chip RX");
    //     // send_link_word(32'h0000_0010);
    //     // send_link_word(32'h0102_0304);
    //     // send_link_word(32'h0506_0708);
    //     repeat (200) @(posedge core_clk);

    //     repeat(5000) @(posedge core_clk);
    //     $finish;
    // end

    // Test sequence hardware-based
    enum logic [3:0] {init = 4'h0, fpga_tx_async_assert = 4'h1, fpga_tx_async_deassert = 4'h2,
                       fpga_tx_io_deassert = 4'h4, hard_rst_deassert = 4'h5, fpga_rx_io_deassert = 4'h6,
                       core_reset_deassert = 4'h7, start_main = 4'h8
                     } reset_seq;

    logic [10:0] wait_amount;
    logic wait_done;


    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            wait_amount      <= 'b0;
            pad_oe           <= '0; 
			wait_done        <= 1'b0;
        end else if (wait_done) begin
            case (reset_seq)
                init                  : wait_amount               <= 11'h8;
                fpga_tx_async_assert  : wait_amount               <= 11'h2;
                fpga_tx_async_deassert: wait_amount               <= 11'h8;
                fpga_tx_io_deassert   : wait_amount               <= 11'h8;
                hard_rst_deassert     : wait_amount               <= 11'd64;  
                fpga_rx_io_deassert   : wait_amount               <= 11'h8;
                core_reset_deassert   : wait_amount               <= 11'd200; 
            endcase
        end else if (wait_amount == 1'b0) begin
            wait_done <= 1'b1;
        end else begin
            wait_amount <= wait_amount - 1'b1;
			wait_done <= 1'b0;
        end

    end


    always_ff @(posedge clk_i) begin 
        if (rst_i) begin
            reset_seq <= init;
        end

        if (wait_done) begin
            case (reset_seq)
                init: begin
                    hard_reset                <= 1'b1;
                    fpga_core_reset           <= 1'b1;
                    fpga_tx_io_link_reset     <= 1'b1;
                    fpga_tx_async_token_reset <= 1'b0;
                    fpga_rx_io_link_reset     <= 1'b1;
                    SS_n                      <= 1'b1;
                    MOSI                      <= 1'b0;
                    trace_enable              <= 1'b0;
                    reset_seq                 <= fpga_tx_async_assert;
                end

                fpga_tx_async_assert: begin
                    reset_seq                 <= fpga_tx_async_deassert;
                    fpga_tx_async_token_reset <= 1'b1;
                end

                fpga_tx_async_deassert: begin
                    reset_seq                 <= fpga_tx_io_deassert;
                    fpga_tx_async_token_reset <= 1'b0;
                end

                fpga_tx_io_deassert: begin
                    reset_seq                 <= hard_rst_deassert;
                    fpga_tx_io_link_reset     <= 1'b0;
                end

                hard_rst_deassert: begin
                    reset_seq                 <= fpga_rx_io_deassert;
                    hard_reset                <= 1'b0;   
                end

                fpga_rx_io_deassert: begin
                    reset_seq                 <= core_reset_deassert;
                    fpga_rx_io_link_reset     <= 1'b0;
                end

                core_reset_deassert: begin
                    reset_seq                 <= start_main;
                    fpga_core_reset           <= 1'b0;    
                end

                start_main: begin
                    trace_enable              <= 1'b1;
                end

                default: reset_seq <= init;
            endcase
        end
    end





    // TRACE REPLAY

    // --- Trace Replay Signals ---

    // Addressing
    logic [31:0] rom_addr_send, rom_addr_recv;
    logic [31+4:0] rom_data_send;
    logic [31+4:0] rom_data_recv;
    logic done_send, done_recv;

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
        .ring_width_p(32)
       ,.rom_addr_width_p(32)
    ) tracer_send (
         .clk_i  (~core_clk) // Run replay on opposite edge for stability
        ,.reset_i(hard_reset)
        ,.en_i   (trace_enable)
        
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
        .ring_width_p(32)
       ,.rom_addr_width_p(32)
    ) tracer_recv (
         .clk_i  (~core_clk)
        ,.reset_i(hard_reset)
        ,.en_i   (1'b1)

        ,.v_i    (dut_v_r)
        ,.data_i (dut_data_r)
        ,.ready_o(tr_ready_lo) // This ready effectively acts as 'yumi' for the DUT

        ,.v_o    ()
        ,.data_o ()
        ,.yumi_i (1'b0)

        ,.rom_addr_o(rom_addr_recv)
        ,.rom_data_i(rom_data_recv)
        ,.done_o    (done_recv)
        ,.error_o   ()
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

endmodule
