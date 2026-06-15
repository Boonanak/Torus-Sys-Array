# Scan-mode constraints for chip_top Tempus DFT timing signoff
#
# Operating assumption (standard scan protocol):
#   - scan_en  (PAD[11]) = 1 throughout the shift operation (case_analysis below)
#   - scan_in  (PAD[46]) driven by tester, changes at FALLING edge of scan_clk
#                         => -clock_fall input_delay models this
#   - scan_out (PAD[47]) captured by tester at RISING edge of scan_clk
#   - scan_clk (PAD[44]) = 20 ns (50 MHz), matching functional core_clk
#
# Why two SDCs (this file vs chip_top.par.sdc):
#   - chip_top.par.sdc is functional mode (scan_en=0, false paths on scan ports)
#   - This SDC is scan shift mode (scan_en=1, scan ports fully constrained)
#   - The two modes are mutually exclusive; they must be separate constraint modes.

set_clock_gating_check -rise -setup 0
set_clock_gating_check -fall -setup 0

# Functional clocks (must be defined to avoid unconstrained-clock warnings;
# all paths on these clocks are false-pathed below since they are inactive during scan)
create_clock [get_ports {PAD[12]}] -name token_clk -period 20.000 -waveform {0.000 10.000}
#create_clock [get_ports {PAD[13]}] -name sclk       -period 250.000 -waveform {0.000 125.000}
create_clock [get_ports {PAD[8]}]  -name dn_clk     -period 40.000  -waveform {0.000 20.000}
set_clock_transition -rise -min 0.1 [get_clocks {token_clk dn_clk}]
set_clock_transition -rise -max 0.1 [get_clocks {token_clk dn_clk}]
set_clock_transition -fall -min 0.1 [get_clocks {token_clk dn_clk}]
set_clock_transition -fall -max 0.1 [get_clocks {token_clk dn_clk}]

# Scan clock: 20 ns (50 MHz) — same port as functional core_clk
create_clock [get_ports {PAD[44]}] -name scan_clk -period 20.000 -waveform {0.000 10.000}
set_clock_transition -rise -min 0.1 [get_clocks {scan_clk}]
set_clock_transition -rise -max 0.1 [get_clocks {scan_clk}]
set_clock_transition -fall -min 0.1 [get_clocks {scan_clk}]
set_clock_transition -fall -max 0.1 [get_clocks {scan_clk}]
set_clock_uncertainty 0.5 [get_clocks {scan_clk token_clk dn_clk}]

set_propagated_clock [get_ports {PAD[12]}]
#set_propagated_clock [get_ports {PAD[13]}]
set_propagated_clock [get_ports {PAD[44]}]
set_propagated_clock [get_ports {PAD[8]}]

# scan_en held HIGH throughout scan shift
set_case_analysis 1 [get_ports {PAD[11]}]

# scan_in (PAD[46]): tester changes data at FALLING edge of scan_clk.
# Data is stable from the falling edge through the next rising edge (capture).
# -clock_fall: reference edge is the falling edge (T=10 in a 20 ns period)
# -max 0 / -min 0: data changes at exactly the falling edge, 0 ns of additional delay.
# => data arrives at first chain flop SI at T = 10 + pad_delay (~10.4 ns)
#    capture rising edge arrives at CP at T = 20 + clock_latency (~21 ns)
#    => large positive setup slack; hold is met since data changed at T=10, not T=0
set_input_delay -clock scan_clk -clock_fall -max 0 [get_ports {PAD[46]}]
set_input_delay -clock scan_clk -clock_fall -min 0 [get_ports {PAD[46]}]

# scan_out (PAD[47]): tester captures at rising edge, 0 ns output delay budget
set_output_delay -clock scan_clk -max 0 [get_ports {PAD[47]}]
set_output_delay -clock scan_clk -min 0 [get_ports {PAD[47]}]

# Generic I/O loads and transitions
set_load 0.005 [all_outputs]
set_input_transition -min 0.1 [all_inputs]
set_input_transition -max 0.5 [all_inputs]

# --- False paths ---
# In scan shift mode only PAD[44]/[11]/[46]/[47] are active.
# All other input and output ports are irrelevant — false-path them systematically
# rather than listing known-problematic ports individually.
# remove_from_collection excludes the four scan ports from the all_inputs/all_outputs set.
set_false_path -from [remove_from_collection \
    [all_inputs] \
    [get_ports {PAD[44] PAD[11] PAD[46]}]]
set_false_path -to [remove_from_collection \
    [all_outputs] \
    [get_ports {PAD[47]}]]

# Also false-path by capture/launch clock for dont_scan_instances whose flops
# run on non-scan clocks (dn_clk/token_clk/sclk) and are excluded from the chain.
# This catches register-to-register paths that the port-based false paths above miss.
set_false_path -from [get_clocks {dn_clk token_clk}]
set_false_path -to   [get_clocks {dn_clk token_clk}]
