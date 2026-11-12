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

    // ---- clock, reset, run switch ----
    // reset synchronized into the 50 MHz domain
    logic rst, rst50, clk, tick;
    rst_gen #(.POR_CYCLES(16)) u_rst50 (.clk_i(CLOCK_50), .rst_async_i(~KEY[0]), .rst_o(rst50));
    rst_slow #(.HOLD(16)) u_rst (.clk_i(clk), .rst_i(rst50), .rst_o(rst));

    // SW[9:6] pick the divide ratio (latched at reset)
    clk_div_sw u_div (.clk_i(CLOCK_50), .rst_i(rst50), .sel_i(SW[9:6]),
                    .clk_o(clk), .tick_o(tick));

    // Scan chain also determines clock
    logic core_clk, scan_clk, clk_drv, clk_chip, scan_mode;
    scan_clk_mux u_scan_div (
        .clk_fast_i(CLOCK_50),
        .clk_run_i(clk),
        .scan_clk_i(scan_clk),
        .scan_mode_i(scan_mode),
        .clk_drv_o(clk_drv),
        .clk_chip_o(clk_chip)
    );

    // Scan control
    logic scan_en, scan_in, scan_out;
    scan_ctrl u_scan_ctrl (
        .clk_i(CLOCK_50), .rst_i(rst50),
        .key_toggle_n_i(KEY[2]), .key_step_n_i(KEY[3]), .key_dump_n_i(KEY[1]), .nsteps_i(SW[9:6]),
        .safe_i(tick),
        .scan_mode_o(scan_mode), .scan_en_o(scan_en), .scan_clk_o(scan_clk), .scan_in_o(scan_in), .scan_out_i(scan_out),
        .out_valid_o(), .out_data_o(),
        .active_o(), .ready_o(), .busy_o()
    );

    logic [1:0] run_s;
    always_ff @(posedge clk) run_s <= {run_s[0], SW[0]};
    wire run = run_s[1];

    logic oe = 1'b0, k1_q = 1'b1;
    always_ff @(posedge CLOCK_50) begin
        k1_q <= KEY[1];
        if (k1_q & ~KEY[1]) oe <= ~oe;     // each press toggles; off at power-up
    end

    // ---- chip-facing signals (names match chip_top) ----
    logic        core_clk, hard_reset;
    logic [16:0] rx_data, tx_data;
    logic        rx_clk, rx_valid, rx_token;
    logic        tx_clk, tx_valid, tx_token;
    logic        scan_en, scan_in, scan_out;

    // ---- driver status ----
    logic        trace_ready, done, error, parity_err, out_valid;
    logic [31:0] send_addr, recv_addr, out_data;

    // ---- Choose benchmark ----
    function automatic logic [2:0] pick_bench(input logic [4:0] s);  // s[4]=SW[5] ... s[0]=SW[1]
        if (s[4:0] == 5'b10001) pick_bench = 3'd6;
        else if (s[4:0] == 5'b10011) pick_bench = 3'd7;
        else if (s[4]) pick_bench = 3'd5;
        else if (s[3]) pick_bench = 3'd4;
        else if (s[2]) pick_bench = 3'd3;
        else if (s[1]) pick_bench = 3'd2;
        else if (s[0]) pick_bench = 3'd1;
        else           pick_bench = 3'd0;      // nothing selected
    endfunction

    logic [4:0] bsw_s1, bsw_s2;
    logic [2:0] bench;
    always_ff @(posedge CLOCK_50) begin
        bsw_s1 <= SW[5:1];
        bsw_s2 <= bsw_s1;
        if (rst50) bench <= pick_bench(bsw_s2);
    end

    driver u_driver (
         .clk_i        (clk)
        ,.rst_i        (rst)
        ,.run_i        (run & (bench != 3'd0))
        ,.bench_i      (bench)
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
        ,.trace_ready_o (trace_ready)
        ,.done_o       (done)
        ,.error_o      (error)
        ,.parity_err_o (parity_err)
        ,.send_addr_o  (send_addr)
        ,.recv_addr_o  (recv_addr)
        ,.out_valid_o  (out_valid)
        ,.out_data_o   (out_data)
    );

    // ---- FPGA -> chip  (GPIO_0, tri-stated unless drive-enable is on) ----
    assign GPIO_0[16:0]  = oe ? rx_data    : {17{1'bz}};
    assign GPIO_0[17]    = oe ? rx_clk     : 1'bz;
    assign GPIO_0[18]    = oe ? rx_valid   : 1'bz;
    assign GPIO_0[19]    = oe ? tx_token   : 1'bz;
    assign GPIO_0[34]    = oe ? core_clk   : 1'bz;
    assign GPIO_0[35]    = oe ? hard_reset : 1'bz;
    assign GPIO_0[20]    = oe ? scan_en    : 1'bz;
    assign GPIO_0[21]    = oe ? scan_in    : 1'bz;
    assign GPIO_0[33:22] = {12{1'bz}};

    logic uart_tx;
    // ---- chip -> FPGA  (GPIO_1, inputs) ----
    assign tx_data  = GPIO_1[16:0];
    assign tx_clk   = GPIO_1[17];
    assign tx_valid = GPIO_1[18];
    assign rx_token = GPIO_1[19];
    assign scan_out = GPIO_1[20];
    assign GPIO_1[20:0]  = {21{1'bz}};     // chip -> FPGA inputs
    assign GPIO_1[21]    = uart_tx;        // UART TX to the PC (3.3 V adapter RX, shared GND)
    assign GPIO_1[35:22] = {14{1'bz}};

    // ---- LEDs, displays, UART ----
    logic [9:0] ledr;
    bringup_io #(.CLK_HZ(50_000_000)) u_io (
         .clk_i        (clk)
        ,.rst_i        (rst)
        ,.run_i        (run)
        ,.trace_ready_i(trace_ready)
        ,.done_i       (done)
        ,.error_i      (error)
        ,.parity_err_i (parity_err & tick)
        ,.send_addr_i  (send_addr)
        ,.recv_addr_i  (recv_addr)
        ,.out_valid_i  (out_valid & tick)
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

    // we sacrifice the trace ready (which was honestly the same as the reset)
    // in favor of knowing whether or not our chip is outputting data
    assign LEDR = {ledr[9:7], oe, ledr[5:0]}; 


endmodule
