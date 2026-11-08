// clk_div_sw.sv  --  clock chosen by switches (replaces clk_div in emu_top)
//
// sel_i = 0..15 sets the clock rate from clk_i (CLOCK_50):
//     N = max(sel_i, 1)      f(clk_o) = 50 MHz / N
//   sel 0,1 -> 50 MHz (clk_o IS clk_i)    sel 2 -> 25 MHz    sel 4 -> 12.5 MHz
//   sel 5 -> 10 MHz   sel 8 -> 6.25 MHz   sel 10 -> 5 MHz    sel 15 -> 3.33 MHz
//
// The switch setting is latched only while rst_i is high, so flipping a switch during
// a run cannot change the clock mid-run; press reset to apply a new setting.
//
// Glitch note: the 50 MHz setting is a plain mux between clk_i and the divided clock.
// A mux like this can produce a runt pulse at the moment it switches. That is safe
// here because it only switches while rst_i is high, and the slow-domain reset
// (rst_gen) stays asserted for 16 more clk_o cycles after release, so nothing that
// could be disturbed is in use yet. Do not drive sel_r from anything that changes
// while the design is running.
//
// tick_o is high for exactly one clk_i cycle per clk_o period, during the first cycle
// after clk_o rises (always high at 50 MHz). At the end of that cycle (the clk_i edge
// where tick_o is sampled high) every flop clocked by clk_o has just taken its new
// value, so slow-domain signals are stable and can be sampled once per slow cycle
// from clk_i.
module clk_div_sw (
     input  logic       clk_i
    ,input  logic       rst_i        // synchronous to clk_i
    ,input  logic [3:0] sel_i        // raw switch inputs (synchronized inside)
    ,output logic       clk_o
    ,output logic       tick_o
);


    logic [3:0]  sel_s1  = 4'd0, sel_s2 = 4'd0;
    logic [3:0]  sel_r   = 4'd4;               // 12.5 MHz until the first reset latches the switches
    logic [15:0] counter = 16'b0;
    logic        clk_q   = 1'b0;

    wire        use50 = (sel_r < 4'd1);                    // 0 -> 50 MHz

    always_ff @(posedge clk_i) begin
        sel_s1 <= sel_i;
        sel_s2 <= sel_s1;
        if (rst_i) sel_r <= sel_s2;
        counter <= counter + 16'b1;
        clk_q   <= clk_o;
    end

    assign clk_o  = use50 ? clk_i : counter[sel_r - 1];
    assign tick_o = use50 | (clk_o & ~clk_q);   // one fast cycle right after each slow rising edge

endmodule


    /* Original module written by Claude - divides clock by sel value

    logic [3:0] sel_s1 = 4'd0, sel_s2 = 4'd0;
    logic [3:0] sel_r  = 4'd4;               // 12.5 MHz until the first reset latches the switches
    logic [3:0] cnt    = 4'd0;
    logic       clk_r  = 1'b0;

    wire       use50 = (sel_r < 4'd2);                    // 0 or 1 -> 50 MHz
    wire [3:0] n     = use50 ? 4'd2 : sel_r;              // ratio for the divided clock (2..15)
    wire [3:0] half  = n >> 1;
    wire       wrap  = (cnt >= (n - 4'd1));               // >= so a smaller n takes effect at once
    wire [3:0] cnt_n = wrap ? 4'd0 : (cnt + 4'd1);

    always_ff @(posedge clk_i) begin
        sel_s1 <= sel_i;
        sel_s2 <= sel_s1;
        if (rst_i) sel_r <= sel_s2;
        cnt   <= cnt_n;
        clk_r <= (cnt_n < half);             // high for the first n/2 counts of each period
    end

    assign clk_o  = use50 ? clk_i : clk_r;
    assign tick_o = use50 | (cnt == 4'd0); */

    /* Edited module adapted by me - divides clock by sel * 1024

    logic [3:0] sel_s1 = 4'd0, sel_s2 = 4'd0;
    logic [3:0] sel_r  = 4'd4;               // 12.5 MHz until the first reset latches the switches
    logic [13:0] cnt   = 4'd0;
    logic       clk_r  = 1'b0;

    wire        use50 = (sel_r < 4'd1);                    // 0 or 1 -> 50 MHz
    wire [13:0] n     = use50 ? 4'd2 : (sel_r << 10);      // ratio for the divided clock (2..15)
    wire [13:0] half  = n >> 1;
    wire        wrap  = (cnt >= (n - 4'd1));               // >= so a smaller n takes effect at once
    wire [13:0] cnt_n = wrap ? 4'd0 : (cnt + 4'd1);

    always_ff @(posedge clk_i) begin
        sel_s1 <= sel_i;
        sel_s2 <= sel_s1;
        if (rst_i) sel_r <= sel_s2;
        cnt   <= cnt_n;
        clk_r <= (cnt_n < half);             // high for the first n/2 counts of each period
    end

    assign clk_o  = use50 ? clk_i : clk_r;
    assign tick_o = use50 | (cnt == 4'd0);

    */

    /* Newest module adapted by me - divides clock using sel as the index */