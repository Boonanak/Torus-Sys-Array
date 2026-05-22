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
    inout wire [47:0] PAD,
    inout wire VDDPST,
    inout wire VSSPST,
    inout wire VDD,
    inout wire VSS
);


    // Pad ring control vectors
    reg [47:0] I;       // Output data to PAD
    reg [47:0] DS;      // Drive strength control
    reg [47:0] OEN;     // Output enable (active-low)
    reg [47:0] PE;      // Pull-down enable
    reg [47:0] IE;      // Input enable
    wire [47:0] C;      // Input data from PAD


    pad_ring_64 u_pad_ring (
        .I      (I),
        .DS     (DS),
        .OEN    (OEN),
        .PE     (PE),
        .IE     (IE),
        .C      (C),
        .PAD    (PAD),
        .VDDPST (VDDPST),
        .VSSPST (VSSPST),
        .VDD    (VDD),
        .VSS    (VSS)
    );


    // ----- Pad index parameters (must match pcb_jumper_layout.md) -----
    // Global control
    localparam int CORE_CLK_PAD          = 44;
    localparam int HARD_RESET_PAD        = 45;


    // Bsg_link RX (FPGA -> ASIC)
    localparam int DN_CLK_PAD            = 8;
    localparam int DN_VALID_PAD          = 9;
    localparam int DN_TOKEN_PAD          = 10;


    // Bsg_link TX (ASIC -> FPGA)
    localparam int TOKEN_CLK_PAD         = 12;
    localparam int UP_VALID_PAD          = 14;
    localparam int UP_CLK_PAD            = 15;


    // SPI
    // localparam int SCLK_PAD              = 13;
    // localparam int MOSI_PAD              = 24;
    // localparam int MISO_PAD              = 25;
    // localparam int SS_N_PAD              = 26;


    // BLE modulator output
    localparam int PIN_18_PAD            = 27;


    // DFT scan
    localparam int SCAN_EN_PAD           = 11;
    localparam int SCAN_IN_PAD           = 46;
    localparam int SCAN_OUT_PAD          = 47;


    // ----- Per-bit dn_data PAD index lookup -----
    // dn_data[0..7] live on PAD[0..7] (top side, 2x4 jumper grid 1).
    // dn_data[8..15] live on PAD[36..43] in an interleaved pattern dictated
    // by the schematic: P1 pin 1=PAD37=dn_data[8], pin 2=PAD36=dn_data[9],
    // pin 3=PAD39=dn_data[10], pin 4=PAD38=dn_data[11], etc.
    function automatic int dn_data_pad(input int bit_idx);
        case (bit_idx)
            0:  dn_data_pad = 0;
            1:  dn_data_pad = 1;
            2:  dn_data_pad = 2;
            3:  dn_data_pad = 3;
            4:  dn_data_pad = 4;
            5:  dn_data_pad = 5;
            6:  dn_data_pad = 6;
            7:  dn_data_pad = 7;
            8:  dn_data_pad = 37;
            9:  dn_data_pad = 36;
            10: dn_data_pad = 39;
            11: dn_data_pad = 38;
            12: dn_data_pad = 41;
            13: dn_data_pad = 40;
            14: dn_data_pad = 43;
            15: dn_data_pad = 42;
            16: dn_data_pad = 27;
            default: dn_data_pad = 0;
        endcase
    endfunction


    // up_data[0..7] live on PAD[16..23] (left side, 2x4 jumper grid 3),
    // interleaved: P2 pin 17=PAD15=??, ... Actually our left-side mapping
    // is up_data[0..7] -> PAD[22, 23, 20, 21, 18, 19, 16, 17].
    // up_data[8..15] live on PAD[28..35] sequentially.
    function automatic int up_data_pad(input int bit_idx);
        case (bit_idx)
            0:  up_data_pad = 22;
            1:  up_data_pad = 23;
            2:  up_data_pad = 20;
            3:  up_data_pad = 21;
            4:  up_data_pad = 18;
            5:  up_data_pad = 19;
            6:  up_data_pad = 16;
            7:  up_data_pad = 17;
            8:  up_data_pad = 28;
            9:  up_data_pad = 29;
            10: up_data_pad = 30;
            11: up_data_pad = 31;
            12: up_data_pad = 32;
            13: up_data_pad = 33;
            14: up_data_pad = 34;
            15: up_data_pad = 35;
            16: up_data_pad = 13;
            default: up_data_pad = 28;
        endcase
    endfunction


    // ----- Tap nets from C[] / drive nets toward I[] -----
    wire core_clk;
    wire hard_reset;
    wire hard_reset_sync;   // async-assert / sync-deassert version of hard_reset


    wire dn_clk;
    wire dn_valid;
    wire [17:0] dn_data;
    wire dn_token;            // chip output, drives PAD[10]


    wire token_clk;
    wire up_clk;              // chip output, drives PAD[15]
    wire up_valid;            // chip output, drives PAD[14]
    wire [17:0] up_data;      // chip outputs


    // wire sclk_in;
    // wire mosi_in;
    // wire ss_n_in;
    // wire miso_out;


    wire pin_18_out;


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
    wire downstream_io_link_reset_int = hard_reset_sync || (reset_cnt < 6'd28);


    // core link reset: released last (~32 cycles after hard_reset_sync).
    wire core_link_reset_int = hard_reset_sync || (reset_cnt < 6'd32);


    // ----- Tap clocks/inputs from pad ring -----
    assign core_clk    = C[CORE_CLK_PAD];
    assign hard_reset  = C[HARD_RESET_PAD];


    // Synchronize hard_reset deassert into core_clk domain.
    // Assert is still combinationally fast (2-FF chain clears asynchronously).
    async_rst_sync_deassert u_hard_reset_sync (
        .clk                    (core_clk),
        .rst                    (hard_reset),
        .async_rst_sync_deassert(hard_reset_sync)
    );


    assign dn_clk      = C[DN_CLK_PAD];
    assign dn_valid    = C[DN_VALID_PAD];
    assign token_clk   = C[TOKEN_CLK_PAD];


    // assign sclk_in     = C[SCLK_PAD];
    // assign mosi_in     = C[MOSI_PAD];
    // assign ss_n_in     = C[SS_N_PAD];


    // RX data: gather 16 bits from interleaved PAD indices.
    genvar dn_i;
    generate
        for (dn_i = 0; dn_i < 17; dn_i = dn_i + 1) begin : gen_dn_data
            assign dn_data[dn_i] = C[dn_data_pad(dn_i)];
        end
    endgenerate


`ifdef DFT_EN
    // Naive scan chain. Buffer cells give Genus named pins (instance/Z,
    // instance/I) to use as DFT control points referenced by cfg/dft.yml.
    wire scan_en, scan_in, scan_out, scan_out_d;
    BUFFD0BWP7T u_scan_en_buf  (.I(C[SCAN_EN_PAD]), .Z(scan_en));   // scan_en_port
    BUFFD0BWP7T u_scan_in_buf  (.I(C[SCAN_IN_PAD]), .Z(scan_in));   // scan_in_port
    BUFFD0BWP7T u_scan_out_buf (.I(scan_out),       .Z(scan_out_d));// scan_out_port
`endif


    // ----- Default pad configuration + per-pad overrides -----
    integer k;
    always_comb begin
        // Defaults: all pads input-disabled, output-disabled, no PD, low DS.
        for (k = 0; k < 48; k = k + 1) begin
            IE[k]  = 1'b0;
            OEN[k] = 1'b1;
            PE[k]  = 1'b0;
            DS[k]  = 1'b0;
            I[k]   = 1'b0;
        end


        // Inputs (chip listens; OEN=1 keeps driver disabled, IE=1 enables receiver).
        IE[CORE_CLK_PAD]   = 1'b1;
        IE[HARD_RESET_PAD] = 1'b1;
        IE[DN_CLK_PAD]     = 1'b1;
        IE[DN_VALID_PAD]   = 1'b1;
        IE[TOKEN_CLK_PAD]  = 1'b1;
        //IE[SCLK_PAD]       = 1'b1;
        //IE[MOSI_PAD]       = 1'b1;
        //IE[SS_N_PAD]       = 1'b1;
        for (k = 0; k < 17; k = k + 1) begin
            IE[dn_data_pad(k)] = 1'b1;
        end


        // Outputs (chip drives).
        OEN[DN_TOKEN_PAD]  = 1'b0; I[DN_TOKEN_PAD]  = dn_token;
        OEN[UP_CLK_PAD]    = 1'b0; I[UP_CLK_PAD]    = up_clk;
        OEN[UP_VALID_PAD]  = 1'b0; I[UP_VALID_PAD]  = up_valid;
        //OEN[MISO_PAD]      = 1'b0; I[MISO_PAD]      = miso_out;
        //OEN[PIN_18_PAD]    = 1'b0; I[PIN_18_PAD]    = pin_18_out;
        for (k = 0; k < 17; k = k + 1) begin
            OEN[up_data_pad(k)] = 1'b0;
            I[up_data_pad(k)]   = up_data[k];
        end


`ifdef DFT_EN
        IE[SCAN_EN_PAD]  = 1'b1; OEN[SCAN_EN_PAD]  = 1'b1;
        IE[SCAN_IN_PAD]  = 1'b1; OEN[SCAN_IN_PAD]  = 1'b1;
        IE[SCAN_OUT_PAD] = 1'b0; OEN[SCAN_OUT_PAD] = 1'b0; I[SCAN_OUT_PAD] = scan_out_d;
`endif
    end


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
    assign link_rx_parity_high = link_rx_data[35];
    assign link_rx_data_real[15:0]  = link_rx_data[15:0];
    assign link_rx_parity_low = link_rx_data[16];
    // assign dn_data_extended = {1'b0, dn_data[16:0]};
    // assign up_data = up_data_extended[16:0];
    assign dn_data[17] = 1'b0;


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
        .downstream_io_link_reset_i(downstream_io_link_reset_int),
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


    // ----- Student-editable design instance -----
    // top u_soc_top (
    //     .CLK              (core_clk),
    //     .hard_reset       (core_link_reset_int),


    //     // SPI (config write path A)
    //     .SCLK             (sclk_in),
    //     .MOSI             (mosi_in),
    //     .MISO             (miso_out),
    //     .SS_n             (ss_n_in),


    //     // bsg_link (config write path B + status return)
    //     .link_rx_data_i   (link_rx_data),
    //     .link_rx_valid_i  (link_rx_valid),
    //     .link_rx_yumi_o   (link_rx_yumi),
    //     .link_tx_data_o   (link_tx_data),
    //     .link_tx_valid_o  (link_tx_valid),
    //     .link_tx_ready_i  (link_tx_ready),


    //     // BLE modulator output
    //     .PIN_18           (pin_18_out)
    // );


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


// -----------------------------------------------------------------------
// pad_ring_64 — instantiates 48 PDDW1216CDG bidirectional IO pads
// plus 4 corner power/ground pads per chip side.
// -----------------------------------------------------------------------
module pad_ring_64 (
    input  wire [47:0] I,
    input  wire [47:0] DS,
    input  wire [47:0] OEN,
    input  wire [47:0] PE,
    input  wire [47:0] IE,
    output wire [47:0] C,
    inout  wire [47:0] PAD,
    inout  wire        VDDPST,
    inout  wire        VSSPST,
    inout  wire        VDD,
    inout  wire        VSS
);


    PVDD2POC Pad_VDDPST_top    (.VDDPST(VDDPST));
    PVSS2CDG Pad_VSSPST_top    (.VSSPST(VSSPST));
    PVDD1CDG Pad_VDD_top       (.VDD(VDD));
    PVSS1CDG Pad_VSS_top       (.VSS(VSS));


    PVDD2CDG Pad_VDDPST_bottom (.VDDPST(VDDPST));
    PVSS2CDG Pad_VSSPST_bottom (.VSSPST(VSSPST));
    PVDD1CDG Pad_VDD_bottom    (.VDD(VDD));
    PVSS1CDG Pad_VSS_bottom    (.VSS(VSS));


    PVDD2CDG Pad_VDDPST_left   (.VDDPST(VDDPST));
    PVSS2CDG Pad_VSSPST_left   (.VSSPST(VSSPST));
    PVDD1CDG Pad_VDD_left      (.VDD(VDD));
    PVSS1CDG Pad_VSS_left      (.VSS(VSS));


    PVDD2CDG Pad_VDDPST_right  (.VDDPST(VDDPST));
    PVSS2CDG Pad_VSSPST_right  (.VSSPST(VSSPST));
    PVDD1CDG Pad_VDD_right     (.VDD(VDD));
    PVSS1CDG Pad_VSS_right     (.VSS(VSS));


    genvar i;
    generate
        for (i = 0; i < 48; i = i + 1) begin: Pad_IO
            PDDW1216CDG in_out (
                .C   (C[i]),
                .DS  (DS[i]),
                .OEN (OEN[i]),
                .PAD (PAD[i]),
                .I   (I[i]),
                .PE  (PE[i]),
                .IE  (IE[i])
            );
        end
    endgenerate


endmodule
