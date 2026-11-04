// emu_top.sv  --  DE1-SoC top level for EMULATION
// The chip's RTL (chip_top) runs inside the FPGA and is driven by `driver`
// over the same bsg_link wires the real chip will use.
//
// Board use:
//   KEY[0]  reset (press)       SW[0]  run the trace
//   LEDR / HEX / UART: see bringup_io in bringup_common.sv
//   GPIO_0[0] = UART TX to the PC (3.3 V USB-serial adapter RX; share GND)
//
// Port names match Terasic's DE1-SoC pin-assignment file, so you can import
// that file (Assignments > Import Assignments) instead of typing pins.
module emu_top (
     input  logic        CLOCK_50
    ,input  logic [3:0]  KEY
    ,input  logic [9:0]  SW
    ,output logic [9:0]  LEDR
    ,output logic [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5
    ,inout  wire  [35:0] GPIO_0
);

    // 50 MHz / CLK_DIV. Start slow; raise it once everything works.
    localparam int CLK_DIV = 4;                       // 12.5 MHz
    localparam int CLK_HZ  = 50_000_000 / CLK_DIV;

    // ---- clock, reset, run switch ----
    logic clk, rst;
    clk_div #(.DIV(CLK_DIV)) u_div (.clk_i(CLOCK_50), .clk_o(clk));
    rst_gen #(.POR_CYCLES(16)) u_rst (.clk_i(clk), .rst_async_i(~KEY[0]), .rst_o(rst));

    logic [1:0] run_s;
    always_ff @(posedge clk) run_s <= {run_s[0], SW[0]};
    wire run = run_s[1];

    // ---- wires between the driver and the chip (names match chip_top) ----
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

    // assign done = 0;
    // assign error = 0;
    // assign parity_err = 0;
    // assign send_addr = 5;
    // assign recv_addr = 10;
    // assign out_valid = 0;
    // assign out_data = 0;

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

    // ---- LEDs, displays, UART ----
    logic uart_tx;
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
        ,.ledr_o       (LEDR)
        ,.hex0_o       (HEX0)
        ,.hex1_o       (HEX1)
        ,.hex2_o       (HEX2)
        ,.hex3_o       (HEX3)
        ,.hex4_o       (HEX4)
        ,.hex5_o       (HEX5)
        ,.uart_tx_o    (uart_tx)
    );

    assign GPIO_0[0]    = uart_tx;
    assign GPIO_0[35:1] = {35{1'bz}};

endmodule
