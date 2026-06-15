#------------------------------------------------------------------------
# Clock Definitions
#
# Two clock-rate budgets: a 100 MHz core/TX rate and a 50 MHz IO-side
# rate for the FPGA-forwarded clocks. The split tracks bsg_link_oddr_phy's
# behavior — the PHY divides clk_i by 2 to produce clk_r_o, so a chip
# core_clk of 100 MHz launches a 50 MHz forwarded clock toward the FPGA.
# A symmetric FPGA peer produces a 50 MHz clock back at the chip's RX pad.
#
#   core_clk    on PAD[44] - 50 MHz core/TX master clock
#                            (io_master_clk for bsg_link_ddr_upstream is
#                             tied to core_clk inside chip_top.sv)
#   dn_clk      on PAD[8]  - 25 MHz downstream RX clock from FPGA
#                            (FPGA's bsg_link_oddr_phy ÷2 of its 50 MHz io_clk)
#   token_clk   on PAD[12] - 50 MHz upstream credit-return from FPGA
#                            (driven by FPGA core_token_r_o, lives in FPGA
#                             core domain — bounded at chip core_clk rate)
#
# SPI's SCLK (PAD[13]) is also a clock; treated as a 4 MHz async reference.
#------------------------------------------------------------------------

set FUNC_CLK_PERIOD     20.0    ;# 50 MHz core_clk / token_clk
set IO_CLK_PERIOD       40.0    ;# 25 MHz dn_clk (FPGA forwarded clock, bsg_link_oddr_phy ÷2)
set FUNC_CLK_UNCERT      0.5    ;# clean-PLL or short-trace-FPGA source
set FUNC_CLK_TRANSITION  0.1    ;# rise/fall waveform transition

# Core clock (drives core domain + bsg_link upstream IO domain).
create_clock -name core_clk -period $FUNC_CLK_PERIOD [get_ports PAD[44]]
set_clock_uncertainty $FUNC_CLK_UNCERT     [get_clocks core_clk]
set_clock_transition  -rise $FUNC_CLK_TRANSITION [get_clocks core_clk]
set_clock_transition  -fall $FUNC_CLK_TRANSITION [get_clocks core_clk]

# Downstream IO clock (RX side of bsg_link), 50 MHz from FPGA's oddr_phy.
create_clock -name dn_clk -period $IO_CLK_PERIOD [get_ports PAD[8]]
set_clock_uncertainty $FUNC_CLK_UNCERT     [get_clocks dn_clk]
set_clock_transition  -rise $FUNC_CLK_TRANSITION [get_clocks dn_clk]
set_clock_transition  -fall $FUNC_CLK_TRANSITION [get_clocks dn_clk]

# Token return clock (credit-return side of bsg_link upstream). Each
# rising edge IS one credit returned by the FPGA; declared as a clock
# because it physically drives the bsg_async_credit_counter's w_clk_i.
# Lives in the FPGA's core domain — same 100 MHz rate as core_clk.
create_clock -name token_clk -period $FUNC_CLK_PERIOD [get_ports PAD[12]]
set_clock_uncertainty $FUNC_CLK_UNCERT     [get_clocks token_clk]
set_clock_transition  -rise $FUNC_CLK_TRANSITION [get_clocks token_clk]
set_clock_transition  -fall $FUNC_CLK_TRANSITION [get_clocks token_clk]

# SPI clock: up to 4 MHz (250 ns period).
create_clock -name sclk -period 250.0 [get_ports PAD[13]]
set_clock_uncertainty 5.0 [get_clocks sclk]
set_clock_transition -rise 0.1 [get_clocks sclk]
set_clock_transition -fall 0.1 [get_clocks sclk]

#------------------------------------------------------------------------
# CDC: declare all four clocks asynchronous.
#
# Each link domain has its own bsg_async_fifo / bsg_async_credit_counter,
# so the timing tool should not analyse paths between groups by default.
# Specific gray-code pointer paths are bounded below via set_max_delay.
#------------------------------------------------------------------------
set_clock_groups -asynchronous \
  -group {core_clk}  \
  -group {dn_clk}    \
  -group {token_clk} \
  -group {sclk}

#------------------------------------------------------------------------
# Async-FIFO gray-code CDC: bounded max delay (bsg-canonical pattern)
#
# bsg_async_fifo / bsg_async_credit_counter rely on a Hamming-1 invariant:
# the gray-coded pointer must change at most one bit between any two
# samples taken by the destination-clock synchronizer. set_clock_groups
# above false-paths the launch -> capture edge by default, but with no
# bound the router can let the path stretch arbitrarily — risking the
# launch flop's output skewing past the next sender clock edge and being
# captured as a multi-bit gray-code change.
#
# Budget = HALF the SOURCE clock period, per bsg_tag_timing.tcl's
# bsg_tag_add_client_cdc_timing_constraints proc:
#     "CDC delay corresponds to skew between bits in the sender. We need
#      to make sure that the skew is not greater than the cycle time;
#      conservatively, we set it to one half of the sender cycle time."
#
# Both bsg_async_fifo and bsg_async_credit_counter route their gray
# pointers through bsg_launch_sync_sync (bsg_async_ptr_gray instantiates
# bsg_launch_sync_sync as 'ptr_sync'). The launch FF is bsg_SYNC_LNCH_r;
# the first capture FF is bsg_SYNC_1_r. The hierarchical wildcard catches
# every instance regardless of where it sits in the hierarchy.
#
# Cell-based set_max_delay automatically uses launch/Q -> capture/D pins.
# set_max_delay overrides the implicit false_path from set_clock_groups
# only on these specific pin pairs; the rest of the async paths stay
# false-pathed.
#------------------------------------------------------------------------
set HALF_SRC_PERIOD [expr $FUNC_CLK_PERIOD / 2.0]
set_max_delay $HALF_SRC_PERIOD \
    -from [get_cells -hier -filter "name =~ *bsg_SYNC_LNCH_r_reg*"] \
    -to   [get_cells -hier -filter "name =~ *bsg_SYNC_1_r_reg*"]
set_min_delay 0.0 \
    -from [get_cells -hier -filter "name =~ *bsg_SYNC_LNCH_r_reg*"] \
    -to   [get_cells -hier -filter "name =~ *bsg_SYNC_1_r_reg*"]

#------------------------------------------------------------------------
# Input transitions
#
# Assume each chip input is driven by the same TSMC180 PDDW1216CDG cell
# instance on a peer chip, with default drive strength (DS=0, ~12 mA) and
# a short PCB trace. This gives a clean ~0.5 ns max input transition and
# ~0.1 ns at the fast corner. Applied to all input ports — clock pads
# included, since their slew matters for setup/hold checks against the
# data ports they sample.
#
# Note: this is independent of set_clock_transition above (which sets the
# clock-waveform transition used for skew analysis). Both can coexist;
# the tool uses set_clock_transition for clock paths and the implied
# data transition from set_input_transition for the data paths.
#------------------------------------------------------------------------
set_input_transition -max 0.5 [all_inputs]
set_input_transition -min 0.1 [all_inputs]

# Clock pads need a tighter input slew than data pads — Innovus's CTS
# targets 0.4 ns at the root driver, and a 0.5 ns input slew at the
# clock pad pushes past that and triggers post-CTS slew violations on
# PAD[8/12/13/44]. Override to 0.2 ns max / 0.05 ns min for the four
# clock pads. (Off-chip side: assumed clean low-jitter clock source —
# crystal oscillator or PLL — driving across a short PCB trace.)
set_input_transition -max 0.2  [get_ports {PAD[8] PAD[12] PAD[13] PAD[44]}]
set_input_transition -min 0.05 [get_ports {PAD[8] PAD[12] PAD[13] PAD[44]}]

#------------------------------------------------------------------------
# bsg_link DDR IO timing — center-aligned source-synchronous
#
# bsg_link launches data such that the IO clock edge lands in the MIDDLE
# of each data UI (per bsg_link_oddr_phy.v / bsg_link_iddr_phy.v file
# headers). At 50 MHz IO with DDR, each UI = 10 ns and the clock edge
# is at ±5 ns from each data edge.
#
# RX side (FPGA -> chip): set_input_delay -min/-max on BOTH dn_clk edges
#     describes the data eye as it arrives at the chip pad. The min/max
#     envelope = "data is valid from min_in_dly after the edge to
#     (period/2 - min_in_dly) after the edge."
#
# TX side (chip -> FPGA): set_data_check between up_clk pad and each
#     up_data/up_valid pad. set_data_check directly bounds on-chip skew
#     between two output ports — appropriate here because up_clk is a
#     forwarded clock (generated from io_master_clk) and we don't care
#     about the FPGA's setup/hold spec, only on-chip launch skew.
#     set_multicycle_path 1 fixes the half-period interpretation.
#
# Eye envelope numbers (computed once below, used inline):
#     RX side  (set_input_delay): related period = dn_clk = IO_CLK_PERIOD
#         max_io_skew_rx  = io_clk_period * 0.025
#         min_input_delay = max_io_skew_rx + clk_uncert + cell_rf/2
#         max_input_delay = io_clk_period/2 - min_input_delay - dn_clk_pad_lat
#     TX side  (set_data_check): related period = core_clk = FUNC_CLK_PERIOD
#         max_io_skew_tx  = func_clk_period * 0.025
#         data_check      = func_clk_period/2 - max_io_skew_tx
#                          - tx_launch_skew - clk_uncert - cell_rf/2
#
# Why two periods: bsg_link_oddr_phy halves clk_i to produce clk_r_o, so
# the chip-side TX uses the io_master_clk = core_clk (50 MHz, 20 ns)
# rate for set_data_check transitions at PAD[15], while the chip-side RX
# samples dn_clk (25 MHz, 40 ns) which is the FPGA's *already-halved*
# forwarded clock at PAD[8].
#------------------------------------------------------------------------

# Eye-envelope constants.
#
# - PAD_RF: PDDW1216CDG rise/fall transition mismatch.
#
# - DN_CLK_PAD_LAT: PDDW1216CDG PAD->C input-buffer delay (~1 ns at WCCOM).
#   Subtracted from MAX_IN_DLY so the eye envelope budgets the chip's
#   input pad delay on the data path. (We tried the cleaner-looking
#   set_clock_latency on dn_clk — Cadence applies it asymmetrically as
#   src-latency on the launch side and net-latency on the capture side
#   for input data paths, and set_propagated_clock only overrides the
#   capture half. Net effect post-CTS: the launch annotation persists
#   and *adds* to data-port arrival, leaving ~-0.4 ns RX setup violations
#   on iddr_phy/data_p_r. Plain subtraction is a constant offset that
#   works the same pre- and post-CTS.)
#
# - TX_LAUNCH_SKEW: set to 0.0 — keep the set_data_check window at the
#   bsg-canonical value and let PAR balance up_clk vs up_data.
#   At 50 MHz the scan-flop CP->Q asymmetry (~1.5 ns, data flops are
#   SDFQD0BWP7T ~2 ns vs clk_r_o non-scan ~0.3 ns) causes only a
#   ~0.65 ns violation, which PAR can close by adding a small buffer on
#   the up_clk output net.  Set to 1.5 ns to relax instead if PAR fails.
set BSG_LINK_TX_IO_PERIOD    $FUNC_CLK_PERIOD                      ;# 20 ns: clk_r_o transitions at this rate
set BSG_LINK_RX_IO_PERIOD    $IO_CLK_PERIOD                        ;# 40 ns: dn_clk at chip pad
set BSG_LINK_TX_IO_SKEW      [expr 0.025 * $BSG_LINK_TX_IO_PERIOD] ;# 2.5% of TX period (bsg-canonical)
set BSG_LINK_RX_IO_SKEW      [expr 0.025 * $BSG_LINK_RX_IO_PERIOD] ;# 2.5% of RX period
set BSG_LINK_PAD_RF          0.1                                   ;# PDDW1216CDG rise/fall mismatch
set BSG_LINK_DN_CLK_PAD_LAT  1.0                                   ;# PDDW1216CDG PAD->C input-buffer delay
set BSG_LINK_TX_LAUNCH_SKEW  1.5                                   ;# relax set_data_check window to absorb up_clk vs up_data launch skew
set BSG_LINK_MIN_IN_DLY      [expr $BSG_LINK_RX_IO_SKEW + $FUNC_CLK_UNCERT + $BSG_LINK_PAD_RF / 2.0]
set BSG_LINK_MAX_IN_DLY      [expr ($BSG_LINK_RX_IO_PERIOD / 2.0) - $BSG_LINK_MIN_IN_DLY - $BSG_LINK_DN_CLK_PAD_LAT]
set BSG_LINK_DCHK            [expr ($BSG_LINK_TX_IO_PERIOD / 2.0) - $BSG_LINK_TX_IO_SKEW - $BSG_LINK_TX_LAUNCH_SKEW - $FUNC_CLK_UNCERT - $BSG_LINK_PAD_RF / 2.0]

# bsg-canonical RX/TX procs, copied verbatim from BaseJump STL's
# `hard/gf_14/bsg_link/tcl/bsg_link_ddr.constraints.tcl` (Paul Gao 2021,
# bsg_link_ddr_in_constraints + bsg_link_ddr_out_constraints).
# We pass our project-specific eye numbers (above) as arguments and let
# the procs emit the 4 set_input_delay lines per RX-port-list and the
# 2 set_data_check + 2 set_multicycle_path lines per TX port.
proc bsg_link_ddr_in_constraints {clk_name ports max_delay min_delay} {
  set_input_delay -max $max_delay -clock $clk_name -source_latency_included -network_latency_included $ports
  set_input_delay -max $max_delay -clock $clk_name -source_latency_included -network_latency_included $ports -add_delay -clock_fall
  set_input_delay -min $min_delay -clock $clk_name -source_latency_included -network_latency_included $ports
  set_input_delay -min $min_delay -clock $clk_name -source_latency_included -network_latency_included $ports -add_delay -clock_fall
}

proc bsg_link_ddr_out_constraints {clk_port ports setup_time hold_time} {
  foreach_in_collection obj $ports {
    set_data_check -from $clk_port -to $obj -setup $setup_time
    set_data_check -from $clk_port -to $obj -hold  $hold_time
    set_multicycle_path -end   -setup 1 -to $obj
    set_multicycle_path -start -hold  0 -to $obj
  }
}

# RX (FPGA -> chip): dn_clk samples dn_data[15:0] + dn_valid.
#   dn_data[0..7]   -> PAD[0..7]
#   dn_data[8..15]  -> PAD[37,36,39,38,41,40,43,42]   (interleaved per chip_top.sv)
#   dn_valid        -> PAD[9]
bsg_link_ddr_in_constraints dn_clk \
  [get_ports {PAD[0] PAD[1] PAD[2] PAD[3] PAD[4] PAD[5] PAD[6] PAD[7] PAD[37] PAD[36] PAD[39] PAD[38] PAD[41] PAD[40] PAD[43] PAD[42] PAD[27]}] \
  $BSG_LINK_MAX_IN_DLY \
  $BSG_LINK_MIN_IN_DLY

# TX (chip -> FPGA): up_clk on PAD[15] forwards up_data[15:0] + up_valid.
#   up_data[0..7]   -> PAD[22,23,20,21,18,19,16,17]   (interleaved)
#   up_data[8..15]  -> PAD[28..35] sequentially
#   up_valid        -> PAD[14]
bsg_link_ddr_out_constraints \
  [get_ports PAD[15]] \
  [get_ports {PAD[22] PAD[23] PAD[20] PAD[21] PAD[18] PAD[19] PAD[16] PAD[17] PAD[28] PAD[29] PAD[30] PAD[31] PAD[32] PAD[33] PAD[34] PAD[35] PAD[13]}] \
  $BSG_LINK_DCHK \
  $BSG_LINK_DCHK

# dn_token output (PAD[10]) is the chip's RX-side credit return — it
# functions as a clock to the FPGA's bsg_async_credit_counter, not as
# data. bsg_chip leaves the analogous p_sdi_token_o intentionally
# unconstrained (hard to predict launch delay before CTS).

#------------------------------------------------------------------------
# Other input / output delays (SPI)
#------------------------------------------------------------------------

# SPI inputs (MOSI on PAD[24], SS_n on PAD[26]) relative to SCLK.
#set_input_delay 125.0 -max -clock [get_clocks sclk] [get_ports {PAD[24] PAD[26]}]
#set_input_delay 0.0   -min -clock [get_clocks sclk] [get_ports {PAD[24] PAD[26]}]

# MISO timing (PAD[25] driven from core_clk domain, sampled externally by SCLK).
# Reference SCLK (4 MHz, 250 ns period), not core_clk: the FPGA actually
# samples MISO with SCLK, and core_clk's BCCOM-corner ideal/early arrival
# was producing phantom hold violations on PAD[25] (data appearing at
# the pad "before" the core_clk edge in fast-corner view). The 4 MHz
# SPI clock has 250 ns of head-room so the absolute numbers are slack-rich.
# (set_clock_groups -asynchronous already isolates SCLK from core_clk,
# so this constraint doesn't conflict with the on-chip CDC plumbing.)
#set_output_delay 50.0 -max -clock [get_clocks sclk] [get_ports PAD[25]]
#set_output_delay 0.0  -min -clock [get_clocks sclk] [get_ports PAD[25]]

#------------------------------------------------------------------------
# False paths on externally-controlled async resets / synchronized inputs
#------------------------------------------------------------------------

# Hard reset (PAD[45]) — synchronized internally by async_rst_sync_deassert.
set_false_path -from [get_ports PAD[45]] -to [all_registers]

# SPI handshakes are synchronized inside spi_slave.
#set_false_path -from [get_ports PAD[26]] -to [all_registers]   ;# SS_n
#set_false_path -from [get_ports PAD[13]] -to [all_registers]   ;# SCLK as data
#set_false_path -from [get_ports PAD[24]] -to [all_registers]   ;# MOSI

#------------------------------------------------------------------------
# Generic IO load
#------------------------------------------------------------------------
set_load 1 [all_outputs]

#------------------------------------------------------------------------
# Design rule constraints
#
# set_max_transition: limits signal slew on internal nets. Without this
# the tool only fixes transitions that cause timing violations — slow slews
# on non-critical nets go undetected and increase delay/power downstream.
# 1.5 ns = 7.5% of the 20 ns core period; relaxed to 3.0 ns at output
# ports since off-chip slew is dominated by PCB load, not on-chip buffering.
#
# set_max_fanout: caps logical fanout per cell output. Genus/Innovus
# already buffer high-fanout nets for timing, but an explicit limit ensures
# fanout is controlled even on non-critical (slack-rich) paths.
# 20 is a typical value for TSMC 180nm at this frequency.
#------------------------------------------------------------------------
set_max_transition 1.5 [current_design]
set_max_transition 3.0 [all_outputs]
set_max_fanout 20 [current_design]


#------------------------------------------------------------------------
# Scan chain I/O timing (DFT mode; PAD[11]=scan_en, PAD[46]=scan_in,
# PAD[47]=scan_out — active only during test, not during functional op).
#------------------------------------------------------------------------
set_false_path -from [get_ports PAD[11]] -to [all_registers]
set_false_path -from [get_ports PAD[46]] -to [all_registers]
set_false_path -from [all_registers]     -to [get_ports PAD[47]]
