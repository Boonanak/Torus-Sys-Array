// board_top.sv  --  DE1-SoC top level for the REAL CHIP
// `driver` is unchanged from emulation; chip_top is not instantiated. The
// chip-facing wires go out to the GPIO headers instead.
//
// Board use:
//   KEY[0]  reset (press)    SW[0]  run the trace    SW[9]  DRIVE ENABLE
//   LEDR[8] shows drive enable.  Other LEDs / HEX / UART: see bringup_io.
//
// *** SAFETY ***
//   SW[9] controls whether the FPGA drives any pin toward the chip. With it
//   OFF every chip-facing pin is high-impedance. Do not drive an unpowered
//   chip (current can flow back through its pad protection diodes). Power the
//   chip first, with a current-limited supply, then turn SW[9] on.
//   The DE1-SoC GPIO is 3.3 V: confirm that matches the chip's pad supply
//   (VDDPST) before connecting anything.
//
// *** PIN MAP: PLACEHOLDER ***
//   The indices below are NOT taken from your PCB. They split the signals so
//   GPIO_0 = chip -> FPGA and GPIO_1 = FPGA -> chip, which keeps the direction
//   logic simple. Re-map them to match the master PCB's wiring/jumpers.
//   Put tx_clk (the chip's forwarded clock) on a clock-capable input pin.
module board_top (
     input  logic        CLOCK_50
    ,input  logic [3:0]  KEY
    ,input  logic [9:0]  SW
    ,output logic [9:0]  LEDR
    ,output logic [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5
    ,inout  wire  [35:0] GPIO_0     // chip -> FPGA, plus UART TX
    ,inout  wire  [35:0] GPIO_1     // FPGA -> chip
);

    // The chip was synthesized for a faster clock; start the first bring-up slowly.
    localparam int CLK_DIV = 10;                      // 5 MHz
    localparam int CLK_HZ  = 50_000_000 / CLK_DIV;

    // ---- clock, reset, switches ----
    logic clk, rst;
    clk_div #(.DIV(CLK_DIV)) u_div (.clk_i(CLOCK_50), .clk_o(clk));
    rst_gen #(.POR_CYCLES(16)) u_rst (.clk_i(clk), .rst_async_i(~KEY[0]), .rst_o(rst));

    logic [1:0] run_s, oe_s;
    always_ff @(posedge clk) begin
        run_s <= {run_s[0], SW[0]};
        oe_s  <= {oe_s[0],  SW[9]};
    end
    wire run = run_s[1];
    wire oe  = oe_s[1];

    // ---- chip-facing signals (names match chip_top) ----
    logic        core_clk, hard_reset;
    logic [16:0] rx_data, tx_data;
    logic        rx_clk, rx_valid, rx_token;
    logic        tx_clk, tx_valid, tx_token;
    logic        scan_en, scan_in, scan_out;

    // ---- driver status ----
    logic        done, error, parity_err, out_valid;
    logic [31:0] send_addr, recv_addr, out_data;

    driver u_driver (
         .clk_i        (clk)
        ,.rst_i        (rst)
        ,.run_i        (run)
        ,.core_clk     (core_clk)
        ,.hard_reset   (hard_reset)
        ,.rx_data      (rx_data)
        ,.rx_clk       (rx_clk)
        ,.rx_valid     (rx_valid)
        ,.rx_token     (rx_token)
        ,.tx_data      (tx_data)
        ,.tx_clk       (tx_clk)
        ,.tx_valid     (tx_valid)
        ,.tx_token     (tx_token)
        ,.scan_en      (scan_en)
        ,.scan_in      (scan_in)
        ,.scan_out     (scan_out)
        ,.done_o       (done)
        ,.error_o      (error)
        ,.parity_err_o (parity_err)
        ,.send_addr_o  (send_addr)
        ,.recv_addr_o  (recv_addr)
        ,.out_valid_o  (out_valid)
        ,.out_data_o   (out_data)
    );

    // ---- FPGA -> chip  (GPIO_1, tri-stated unless drive-enable is on) ----
    assign GPIO_1[16:0]  = oe ? rx_data    : {17{1'bz}};
    assign GPIO_1[17]    = oe ? rx_clk     : 1'bz;
    assign GPIO_1[18]    = oe ? rx_valid   : 1'bz;
    assign GPIO_1[19]    = oe ? tx_token   : 1'bz;
    assign GPIO_1[20]    = oe ? core_clk   : 1'bz;
    assign GPIO_1[21]    = oe ? hard_reset : 1'bz;
    assign GPIO_1[22]    = oe ? scan_en    : 1'bz;
    assign GPIO_1[23]    = oe ? scan_in    : 1'bz;
    assign GPIO_1[35:24] = {12{1'bz}};

    // ---- chip -> FPGA  (GPIO_0, inputs) ----
    assign GPIO_0[16:0]  = {17{1'bz}};
    assign GPIO_0[17]    = 1'bz;
    assign GPIO_0[18]    = 1'bz;
    assign GPIO_0[19]    = 1'bz;
    assign GPIO_0[20]    = 1'bz;
    assign tx_data  = GPIO_0[16:0];
    assign tx_clk   = GPIO_0[17];
    assign tx_valid = GPIO_0[18];
    assign rx_token = GPIO_0[19];
    assign scan_out = GPIO_0[20];

    // ---- LEDs, displays, UART ----
    logic [9:0] ledr;
    logic       uart_tx;
    bringup_io #(.CLK_HZ(CLK_HZ)) u_io (
         .clk_i        (clk)
        ,.rst_i        (rst)
        ,.run_i        (run)
        ,.done_i       (done)
        ,.error_i      (error)
        ,.parity_err_i (parity_err)
        ,.send_addr_i  (send_addr)
        ,.recv_addr_i  (recv_addr)
        ,.out_valid_i  (out_valid)
        ,.out_data_i   (out_data)
        ,.ledr_o       (ledr)
        ,.hex0_o       (HEX0)
        ,.hex1_o       (HEX1)
        ,.hex2_o       (HEX2)
        ,.hex3_o       (HEX3)
        ,.hex4_o       (HEX4)
        ,.hex5_o       (HEX5)
        ,.uart_tx_o    (uart_tx)
    );

    assign LEDR = {ledr[9], oe, ledr[7:0]};

    assign GPIO_0[21]    = uart_tx;
    assign GPIO_0[35:22] = {14{1'bz}};

endmodule
