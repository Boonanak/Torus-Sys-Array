// scan_clk_mux.sv  --  stops the run clock and hands the chip a stepped scan clock.
//
//   clk_drv_o   clock for the driver: the run clock, held LOW while in scan mode
//   clk_chip_o  clock for the chip:   the run clock, or scan_clk_i while in scan mode
//
// The select (sel_g) is a flop on the FALLING edge of the always-running fast clock, so it
// only changes half a cycle after scan_ctrl asked for it. scan_ctrl asks only when
// clk_div_sw says it is safe (safe_o: the run clock is low now and stays low through that
// falling edge), and scan_clk_i is held low outside scan mode. Both mux inputs are therefore
// low whenever the select changes, so no runt pulse reaches the driver or the chip.
module scan_clk_mux (
     input  logic clk_fast_i       // CLOCK_50
    ,input  logic clk_run_i        // selected run clock from clk_div_sw
    ,input  logic scan_clk_i       // registered scan clock from scan_ctrl (low when idle)
    ,input  logic scan_mode_i      // request from scan_ctrl
    ,output logic clk_drv_o
    ,output logic clk_chip_o
);
    logic sel_g = 1'b0;
    always_ff @(negedge clk_fast_i) sel_g <= scan_mode_i;

    assign clk_drv_o  = sel_g ? 1'b0       : clk_run_i;
    assign clk_chip_o = sel_g ? scan_clk_i : clk_run_i;
endmodule
