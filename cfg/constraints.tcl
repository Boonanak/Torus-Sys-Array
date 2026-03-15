# constraints.tcl
#
# This file is where design timing constraints are defined for Genus and Innovus.
# Many constraints can be written directly into the Hammer config files. However, 
# you may manually define constraints here as well.
#

# Defined Variables
set clk_period 12
set half_period [expr {$clk_period / 2}]

# List of feedthough I/O to exclude
set feedthrough_inputs [list transpose ready_i]
set feedthrough_outputs [list ready_o out_data[*][*]]

create_clock -name clk -period $clk_period [get_ports clk_i]
set_clock_uncertainty 0.050 [get_clocks clk]

# Always set the input/output delay as half periods for clock setup checks
set_input_delay $half_period -max -clock [get_clocks clk] [remove_from_collection [all_inputs] [get_ports $feedthrough_inputs]]
set_output_delay $half_period -max -clock [get_clocks clk] [remove_from_collection [remove_from_collection [all_outputs] [get_ports clk_o]] [get_ports $feedthrough_outputs]]

# Constrain feedthrough paths to take less time than max delay
# Add more feedthrough paths as they appear
# half period is very strict, usually at most 0.7 x period, but higher for safety
set_max_delay $half_period -from [get_ports transpose] -to [get_ports {out_data[*][*]}]
set_max_delay $half_period -from [get_ports ready_i] -to [get_ports ready_o]