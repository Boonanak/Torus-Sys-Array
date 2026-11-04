# emu_top.sdc -- minimal constraints for emulation.
# CLK_DIV in emu_top.sv must match -divide_by below (4 -> 12.5 MHz).

create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]

# The divided clock is made by a register inside clk_div, so declare it.
# If the Timing Analyzer says this register wasn't found, run
# "Report Clocks"/"List Registers" and adjust the name pattern.
create_generated_clock -name clk_core -source [get_ports CLOCK_50] -divide_by 4 \
    [get_registers {*u_div*clk_r*}]

derive_clock_uncertainty

# Human-speed board I/O is not timing-critical.
set_false_path -from [get_ports {KEY[*] SW[*]}]
set_false_path -to   [get_ports {LEDR[*] HEX*[*] GPIO_0[*]}]

# NOT constrained yet: the forwarded link clocks between driver and chip
# (rx_clk / tx_clk are made by DDR logic inside the FPGA). The design should
# work at slow clocks without it, but if the link only fails in hardware,
# these crossings are the first suspects.
