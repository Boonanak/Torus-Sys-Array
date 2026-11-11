// scan_ctrl.sv  --  scan-chain control from the FPGA
//
//   KEY[2]  toggle scan mode.  Entering: wait for a safe moment, stop the driver clock and
//           give the chip a held-low scan clock, then raise scan_en.  Leaving: drop scan_en,
//           then restore the run clock.  Back to normal operation exactly where it stopped.
//   KEY[3]  (scan mode) shift N bits, N = SW[9:6] (0 means 16). The clock-select switches are
//           free for this because the clock setting is only latched at reset.
//   KEY[1]  (scan mode) shift SCAN_LEN bits = one full rotation = dump the whole chain.
//
// scan_in is the bit sampled from scan_out just before each clock (recirculation), so after a
// total shift count that is a MULTIPLE OF THE CHAIN LENGTH the chip's state is back exactly as
// it was. Any other total leaves the chain rotated and the chip's state scrambled: finish
// with a full rotation before leaving scan mode (or reset).
//
// Output stream (to the UART FIFO, 32-bit words), per key press:
//     5CA15CA1                     magic
//     00nnnnnn                     number of bits shifted
//     data words                   first bit read = bit 0 of the first word (LSB first);
//                                  the last word is zero-padded
// Each word is followed by WORD_GAP idle cycles so the UART (about 40,000 CLOCK_50 cycles per
// word at 115200 baud) can keep up with its FIFO.
module scan_ctrl #(
     parameter int SCAN_LEN      = 1024
    ,parameter int HALF_CYCLES   = 16      // scan clock half period in clk_i cycles (16 -> 1.56 MHz)
    ,parameter int SETTLE_CYCLES = 16
    ,parameter int WORD_GAP      = 40000   // Changed from 40000 to 400 for simulation
)(
     input  logic        clk_i             // CLOCK_50, always running
    ,input  logic        rst_i             // synchronous to clk_i
    ,input  logic        key_toggle_n_i    // KEY[2]
    ,input  logic        key_step_n_i      // KEY[3]
    ,input  logic        key_dump_n_i      // KEY[1]
    ,input  logic [3:0]  nsteps_i          // SW[9:6]
    ,input  logic        safe_i            // from clk_div_sw
    ,output logic        scan_mode_o       // to scan_clk_mux
    ,output logic        scan_en_o
    ,output logic        scan_clk_o        // registered, low when idle
    ,output logic        scan_in_o         // registered recirculation of scan_out
    ,input  logic        scan_out_i
    ,output logic        out_valid_o       // one-cycle pulses into the UART FIFO
    ,output logic [31:0] out_data_o
    ,output logic        active_o          // not in normal run
    ,output logic        ready_o           // in scan mode, waiting for a key
    ,output logic        busy_o            // shifting / streaming
);

    localparam logic [31:0] MAGIC = 32'h5CA1_5CA1;

    // ---- synchronizers and press detection (KEYs are active low) ----
    logic [1:0] kt_s = 2'b00, ks_s = 2'b00, kd_s = 2'b00, so_s = 2'b00;
    logic [3:0] ns_s1 = 4'd0, ns_s2 = 4'd0;
    logic       kt_q = 1'b0, ks_q = 1'b0, kd_q = 1'b0;
    always_ff @(posedge clk_i) begin
        kt_s  <= {kt_s[0], ~key_toggle_n_i};
        ks_s  <= {ks_s[0], ~key_step_n_i};
        kd_s  <= {kd_s[0], ~key_dump_n_i};
        so_s  <= {so_s[0], scan_out_i};
        ns_s1 <= nsteps_i;
        ns_s2 <= ns_s1;
        kt_q  <= kt_s[1];
        ks_q  <= ks_s[1];
        kd_q  <= kd_s[1];
    end
    wire kt_press = kt_s[1] & ~kt_q;
    wire ks_press = ks_s[1] & ~ks_q;
    wire kd_press = kd_s[1] & ~kd_q;

    typedef enum logic [4:0] {
         S_RUN, S_STOP_REQ, S_STOP_WAIT, S_EN_SETUP, S_IDLE
        ,S_HDR0, S_HDR1, S_SAMPLE, S_SI_WAIT, S_HI, S_LO, S_EMIT, S_GAP
        ,S_EN_OFF, S_RESTORE_REQ, S_RESTORE_WAIT
    } state_e;

    state_e      state = S_RUN, after_gap = S_IDLE;
    logic [16:0] wait_cnt = '0;
    logic [23:0] total_bits = '0, bits_left = '0;
    logic [4:0]  bit_idx = '0;
    logic [31:0] word_sr = '0;

    wire [4:0] step_n = (ns_s2 == 4'd0) ? 5'd16 : {1'b0, ns_s2};

    always_ff @(posedge clk_i) begin
        out_valid_o <= 1'b0;                              // default: pulses
        if (rst_i) begin
            state       <= S_RUN;
            scan_mode_o <= 1'b0;
            scan_en_o   <= 1'b0;
            scan_clk_o  <= 1'b0;
            scan_in_o   <= 1'b0;
            wait_cnt    <= '0;
            bit_idx     <= '0;
            word_sr     <= '0;
        end else begin
            if (wait_cnt != 0) wait_cnt <= wait_cnt - 1'b1;
            case (state)
                S_RUN: if (kt_press) state <= S_STOP_REQ;

                S_STOP_REQ: if (safe_i) begin
                    scan_mode_o <= 1'b1;                  // mux flips half a cycle later
                    wait_cnt    <= SETTLE_CYCLES;
                    state       <= S_STOP_WAIT;
                end
                S_STOP_WAIT: if (wait_cnt == 0) begin
                    scan_en_o <= 1'b1;                    // clock is stopped: safe to raise
                    wait_cnt  <= SETTLE_CYCLES;
                    state     <= S_EN_SETUP;
                end
                S_EN_SETUP: if (wait_cnt == 0) state <= S_IDLE;

                S_IDLE: begin
                    if (kt_press) begin
                        scan_en_o <= 1'b0;
                        wait_cnt  <= SETTLE_CYCLES;
                        state     <= S_EN_OFF;
                    end else if (ks_press) begin
                        total_bits <= {19'd0, step_n};
                        bits_left  <= {19'd0, step_n};
                        state      <= S_HDR0;
                    end else if (kd_press) begin
                        total_bits <= SCAN_LEN;
                        bits_left  <= SCAN_LEN;
                        state      <= S_HDR0;
                    end
                end

                S_HDR0: begin
                    out_valid_o <= 1'b1;  out_data_o <= MAGIC;
                    after_gap   <= S_HDR1;
                    wait_cnt    <= WORD_GAP;  state <= S_GAP;
                end
                S_HDR1: begin
                    out_valid_o <= 1'b1;  out_data_o <= {8'h00, total_bits};
                    after_gap   <= S_SAMPLE;
                    bit_idx     <= '0;    word_sr <= '0;
                    wait_cnt    <= WORD_GAP;  state <= S_GAP;
                end
                S_GAP: if (wait_cnt == 0) state <= after_gap;

                // one bit: sample scan_out, present it on scan_in, then one scan clock pulse
                S_SAMPLE: begin
                    scan_in_o        <= so_s[1];
                    word_sr[bit_idx] <= so_s[1];
                    wait_cnt         <= HALF_CYCLES;
                    state            <= S_SI_WAIT;
                end
                S_SI_WAIT: if (wait_cnt == 0) begin
                    scan_clk_o <= 1'b1;
                    wait_cnt   <= HALF_CYCLES;
                    state      <= S_HI;
                end
                S_HI: if (wait_cnt == 0) begin
                    scan_clk_o <= 1'b0;
                    wait_cnt   <= HALF_CYCLES;
                    state      <= S_LO;
                end
                S_LO: if (wait_cnt == 0) begin
                    bits_left <= bits_left - 1'b1;
                    if (bit_idx == 5'd31 || bits_left == 24'd1) state <= S_EMIT;
                    else begin bit_idx <= bit_idx + 1'b1; state <= S_SAMPLE; end
                end
                S_EMIT: begin
                    out_valid_o <= 1'b1;  out_data_o <= word_sr;
                    word_sr     <= '0;    bit_idx   <= '0;
                    after_gap   <= (bits_left == 24'd0) ? S_IDLE : S_SAMPLE;
                    wait_cnt    <= WORD_GAP;  state <= S_GAP;
                end

                S_EN_OFF: if (wait_cnt == 0) state <= S_RESTORE_REQ;
                S_RESTORE_REQ: if (safe_i) begin
                    scan_mode_o <= 1'b0;
                    wait_cnt    <= SETTLE_CYCLES;
                    state       <= S_RESTORE_WAIT;
                end
                S_RESTORE_WAIT: if (wait_cnt == 0) state <= S_RUN;

                default: state <= S_RUN;
            endcase
        end
    end

    assign active_o = (state != S_RUN);
    assign ready_o  = (state == S_IDLE);
    assign busy_o   = (state == S_HDR0) | (state == S_HDR1) | (state == S_SAMPLE) | (state == S_SI_WAIT)
                    | (state == S_HI)   | (state == S_LO)   | (state == S_EMIT)   | (state == S_GAP);

endmodule
