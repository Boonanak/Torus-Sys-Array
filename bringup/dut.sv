// -----------------------------------------------------------------------
// chip_top.sv
//
// 48-pad TSMC180 wrapper for the EE478b zeroscatter SoC. Integrates:
//   - bsg_link 16-bit DDR upstream + downstream (config writes / status)
//   - SPI slave (alternate path to write the same config registers)
//   - BLE waveform generator (PIN_18 modulator output)
//   - Optional DFT scan chain stitched through PAD[11], PAD[46], PAD[47]
//
// Pad map (matches pcb_jumper_layout.md):
//
//   TOP    PAD[0..7]   = dn_data[7:0]   (RX bus, byte 0, bsg_link grid 1)
//          PAD[8]      = dn_clk
//          PAD[9]      = dn_valid
//          PAD[10]     = dn_token       (output to FPGA RX-side credit return)
//          PAD[11]     = scan_en
//
//   LEFT   PAD[12]     = token_clk      (input from FPGA RX-side)
//          PAD[13]     = SCLK           (SPI clock)
//          PAD[14]     = up_valid       (output)
//          PAD[15]     = up_clk         (output)
//          PAD[16..23] = up_data[6,7,4,5,2,3,0,1] (TX bus, byte 0, bsg_link grid 3)
//
//   BOTTOM PAD[24]     = MOSI
//          PAD[25]     = MISO           (output)
//          PAD[26]     = SS_n
//          PAD[27]     = PIN_18 (BLE modulator output)
//          PAD[28..35] = up_data[8..15] (TX bus, byte 1, bsg_link grid 4)
//
//   RIGHT  PAD[36..43] = dn_data[9,8,11,10,13,12,15,14] (RX byte 1, grid 2)
//          PAD[44]     = core_clk
//          PAD[45]     = hard_reset
//          PAD[46]     = scan_in
//          PAD[47]     = scan_out
//
// io_master_clk_i for bsg_link_ddr_upstream is tied to core_clk_i internally
// to save one pad. All four bsg_link reset inputs are tied to hard_reset.
// -----------------------------------------------------------------------
module chip_top (
    input logic core_clk,
    input logic hard_reset,
    
    // bsg_link downstream data receive
    input  logic [16:0] rx_data,
    input  logic rx_clk,
    output logic rx_token,
    input  logic rx_valid,
    
    // bsg_link upstream data transmit
    output logic [16:0] tx_data,
    output logic tx_clk,
    input  logic tx_token,
    output logic tx_valid,

    input  logic scan_en,
    input  logic scan_in,
    output logic scan_out
);

	// Internal Connections
    wire hard_reset_sync;   // async-assert / sync-deassert version of hard_reset

    wire dn_clk;
    wire dn_valid;
    wire [17:0] dn_data;
    wire dn_token;            // chip output, drives PAD[10]


    wire token_clk;
    wire up_clk;              // chip output, drives PAD[15]
    wire up_valid;            // chip output, drives PAD[14]
    wire [17:0] up_data;      // chip outputs

    // Tie io_master_clk to core_clk to save the PAD that would otherwise
    // carry it. The bsg_link_ddr_upstream's internal CDC degenerates when
    // io_clk_i and core_clk_i are the same net.
    wire io_master_clk = core_clk;

    // ----- Internal reset sequencer for bsg_link init protocol -----
    // bsg_async_credit_counter requires:
    //   1. Assert r_reset (= io_link_reset, on io_clk domain).
    //   2. While r_reset asserted, pulse w_reset (= async_token_reset)
    //      0 -> 1 -> 0 at least once.
    //   3. Wait >=4 r_clock posedges before deasserting r_reset.
    //   4. Deassert r_reset.
    //
    // Tying every link reset to hard_reset would violate that ordering, so
    // the chip generates the staged reset internally from a single counter
    // that starts running once hard_reset deasserts.
    reg [5:0] reset_cnt = 6'd0;
    always @(posedge core_clk) begin
        if (hard_reset_sync)              reset_cnt <= 6'd0;
        else if (reset_cnt < 6'd63)       reset_cnt <= reset_cnt + 6'd1;
    end

    // async_token_reset: 0 normally, pulsed 1 during counts 2..4 after
    // hard_reset_sync deasserts. Held 0 during reset (matches bsg ref tb).
    wire async_token_reset_int = ~hard_reset_sync
                                 && (reset_cnt >= 6'd2)
                                 && (reset_cnt <  6'd5);

    // io_link_resets: held high while reset is asserted, then for
    // ~16 more core_clk cycles after the async_token_reset pulse.
    // upstream (TX) releases first so the other chip's downstream FIFO
    // write-side sees clock edges while its own reset is still asserted,
    // satisfying the BSG sync-reset requirement for bsg_circular_ptr.
    // downstream (RX) holds 12 extra core_clk cycles after upstream releases.
    // UP_CLK is 25 MHz (= core_clk/2), so 12 core cycles = 6 UP_CLK cycles of
    // margin, ensuring the bsg_async_ptr_gray sync-reset fires 4+ times before
    // the RX FIFO write-side reset deasserts.  Stays clear of core_link_reset
    // at cnt=32.
    wire io_link_reset_int            = hard_reset_sync || (reset_cnt < 6'd16);
    wire downstream_io_link_reset_int = hard_reset_sync || (reset_cnt < 6'd24);
    wire downstream_io_link_reset_sync;

    // core link reset: released last (~32 cycles after hard_reset_sync).
    wire core_link_reset_int = hard_reset_sync || (reset_cnt < 6'd32);
    

    // Synchronize hard_reset deassert into core_clk domain.
    // Assert is still combinationally fast (2-FF chain clears asynchronously).
    async_rst_sync_deassert u_hard_reset_sync (
        .clk                    (core_clk),
        .rst                    (hard_reset),
        .async_rst_sync_deassert(hard_reset_sync)
    );


        // chip inputs -> internal link signals
    assign dn_clk    = rx_clk;
    assign dn_data   = {1'b0, rx_data};   // bit 17 is unused
    assign dn_valid  = rx_valid;
    assign token_clk = tx_token;

    // internal link signals -> chip outputs
    assign tx_clk    = up_clk;
    assign tx_data   = up_data[16:0];     // drops the unused bit 17
    assign tx_valid  = up_valid;
    assign rx_token  = dn_token;

    assign scan_out  = 1'b0;              // no scan chain in the FPGA build

    async_rst_sync_deassert u_dn_reset_sync(
        .clk(dn_clk),
        .rst(downstream_io_link_reset_int),
        .async_rst_sync_deassert(downstream_io_link_reset_sync)
    );

    // ----- bsg_link wrapper: 32-bit ready/valid to top.v -----
    wire [35:0] link_rx_data;
    wire        link_rx_valid;
    wire        link_rx_yumi;
    wire [35:0] link_tx_data;
    wire        link_tx_valid;
    wire        link_tx_ready;

    logic [31:0] link_tx_data_real; // FROM CHIP
    logic [31:0] link_rx_data_real; // FROM FPGA
    // logic [17:0] up_data_extended; // FROM CHIP
    // logic [17:0] dn_data_extended; // FROM FPGA

    // PARITY BITS SENT BY FPGA
    logic link_tx_parity_low, link_tx_parity_high;
    // assign link_tx_parity_low = 1'b0;
    // assign link_tx_parity_high = 1'b0;
    parity_generator #(.WIDTH_p(16)) pg_low (
        .bits_i(link_tx_data_real[15:0]),
        .parity_o(link_tx_parity_low)
    );
    parity_generator #(.WIDTH_p(16)) pg_high (
        .bits_i(link_tx_data_real[31:16]),
        .parity_o(link_tx_parity_high)
    );

    logic link_rx_parity_low, link_rx_parity_high;
    logic link_rx_ok_low, link_rx_ok_high;
    logic link_rx_parity_error;
    parity_checker #(.WIDTH_p(16)) check_low (
        .bits_i(link_rx_data[15:0]),
        .parity_i(link_rx_parity_low),
        .is_parity_o(link_rx_ok_low)
    );
    parity_checker #(.WIDTH_p(16)) check_high (
        .bits_i(link_rx_data[33:18]),
        .parity_i(link_rx_parity_high),
        .is_parity_o(link_rx_ok_high)
    );
    assign link_rx_parity_error = link_rx_valid && (!link_rx_ok_low || !link_rx_ok_high);

    assign link_tx_data = {1'b0, link_tx_parity_high, link_tx_data_real[31:16], 1'b0, link_tx_parity_low, link_tx_data_real[15:0]};
    assign link_rx_data_real[31:16] = link_rx_data[33:18];
    assign link_rx_parity_high = link_rx_data[34];
    assign link_rx_data_real[15:0]  = link_rx_data[15:0];
    assign link_rx_parity_low = link_rx_data[16];
    // assign dn_data_extended = {1'b0, dn_data[16:0]};
    // assign up_data = up_data_extended[16:0];


    bsg_link_wrapper #(
        .FLIT_WIDTH    (36),
        .CHANNEL_WIDTH (18)
    ) u_bsg_link_wrapper (
        .core_clk_i                (core_clk),
        .reset_i                   (core_link_reset_int),
        .io_master_clk_i           (io_master_clk),
        .upstream_io_link_reset_i  (io_link_reset_int),
        .async_token_reset_i       (async_token_reset_int),
        .token_clk_i               (token_clk),
        .downstream_io_link_reset_i(downstream_io_link_reset_sync),
        .downstream_io_clk_i       (dn_clk),
        .downstream_io_data_i      (dn_data), // 18 bits
        .downstream_io_valid_i     (dn_valid),
        .upstream_io_clk_r_o       (up_clk),
        .upstream_io_data_r_o      (up_data), // 18 bits
        .upstream_io_valid_r_o     (up_valid),
        .downstream_core_token_r_o (dn_token),
        .rx_data_o                 (link_rx_data), // 18 bits
        .rx_valid_o                (link_rx_valid),
        .rx_yumi_i                 (link_rx_yumi),
        .tx_data_i                 (link_tx_data), // 18 bits
        .tx_valid_i                (link_tx_valid),
        .tx_ready_o                (link_tx_ready)
    );

    top_chip u_soc_top (
        .clk_i(core_clk),
        .reset_i(core_link_reset_int),
        .in_flit(link_rx_data_real),
        .in_flit_v(link_rx_valid),
        .in_flit_par_ok(!link_rx_parity_error),
        .in_flit_ready(link_rx_yumi),
        .link_out_v_o(link_tx_valid),
        .link_out_data_o(link_tx_data_real),
        .link_out_yumi_i(link_tx_ready)
    );

endmodule


// -----------------------------------------------------------------------
// Async assert / sync deassert reset synchronizer.
// -----------------------------------------------------------------------
module async_rst_sync_deassert (
    input  wire clk,
    input  wire rst,
    output wire async_rst_sync_deassert
);
    reg rst_sync1;
    reg rst_sync2;


    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rst_sync1 <= 1'b1;
            rst_sync2 <= 1'b1;
        end else begin
            rst_sync1 <= 1'b0;
            rst_sync2 <= rst_sync1;
        end
    end


    assign async_rst_sync_deassert = rst_sync2;
endmodule
