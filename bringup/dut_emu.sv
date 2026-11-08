// DE1-SoC top level module for FPGA to act as chip
module dut_emu (
     input  logic        CLOCK_50
    ,input  logic [3:0]  KEY
    ,input  logic [9:0]  SW
    ,output logic [9:0]  LEDR
    ,output logic [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5
    ,inout  wire  [35:0] GPIO_0     // chip -> FPGA, plus UART TX
    ,inout  wire  [35:0] GPIO_1     // FPGA -> chip
);

    // Including run logic so we can enable dataflow from chip to FPGA (not necessary though)
    logic [1:0] run_s;
    always_ff @(posedge CLOCK_50) run_s <= {run_s[0], SW[0]};
    wire run = run_s[1];

    // ---- chip-facing signals (names match chip_top) ----
    logic        core_clk, hard_reset;
    logic [16:0] rx_data, tx_data;
    logic        rx_clk, rx_valid, rx_token;
    logic        tx_clk, tx_valid, tx_token;
    logic        scan_en, scan_in, scan_out;

    // ---- FPGA -> chip  (GPIO_1, tri-stated unless drive-enable is on) ----
    assign rx_data    = GPIO_1[16:0];
    assign rx_clk     = GPIO_1[17];
    assign rx_valid   = GPIO_1[18];
    assign tx_token   = GPIO_1[19];
    assign core_clk   = GPIO_1[34];
    assign hard_reset = GPIO_1[35];
    assign scan_en    = GPIO_1[20];
    assign scan_in    = GPIO_1[21];
    assign GPIO_1[35:0] = {36{1'bz}};

    // ---- chip -> FPGA  (GPIO_0, outputs) ----
    assign GPIO_0[16:0]  = tx_data;
    assign GPIO_0[17]    = tx_clk;
    assign GPIO_0[18]    = tx_valid;
    assign GPIO_0[19]    = rx_token;
    assign GPIO_0[20]    = scan_out;
    assign GPIO_0[35:21] = {15{1'bz}};

    // Chip (emulated)
    dut u_chip (
         .core_clk   (core_clk)
        ,.hard_reset (hard_reset)
        ,.rx_data    (rx_data)
        ,.rx_clk     (rx_clk)
        ,.rx_token   (rx_token)
        ,.rx_valid   (rx_valid)
        ,.tx_data    (tx_data)
        ,.tx_clk     (tx_clk)
        ,.tx_token   (tx_token)
        ,.tx_valid   (tx_valid)
        ,.scan_en    (scan_en)
        ,.scan_in    (scan_in)
        ,.scan_out   (scan_out)
    );

    logic [23:0] hb;  logic rxv_seen, txv_seen;
    always_ff @(posedge core_clk) begin
        hb <= hb + 1'b1;                                 // blinks only if the clock wire works
        if (hard_reset) begin rxv_seen <= 1'b0; txv_seen <= 1'b0; end
        else begin
            if (rx_valid) rxv_seen <= 1'b1;
            if (tx_valid) txv_seen <= 1'b1;
        end
    end
    assign LEDR = {hb[23], 3'b0, hard_reset, rxv_seen, txv_seen, 3'b0};
    assign {HEX0, HEX1, HEX2, HEX3, HEX4, HEX5} = {6{7'h7F}};   // blank


endmodule
