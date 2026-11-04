# board_top.sdc -- constraints for driving the real chip.
# Numbers below are for CLK_DIV = 10 (core clock 5 MHz = 200 ns). Recompute
# them if you change CLK_DIV in board_top.sv.

create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]

create_generated_clock -name clk_core -source [get_ports CLOCK_50] -divide_by 10 \
    [get_registers {*u_div*clk_r*}]

# The chip forwards its own clock (core_clk / 2 = 2.5 MHz, 400 ns) on tx_clk.
# GPIO_0[17] is the PLACEHOLDER pin from board_top.sv -- change it if you re-map.
create_clock -name chip_tx_clk -period 400.000 [get_ports {GPIO_0[17]}]

# The two domains are crossed by the link's async FIFOs, so don't time between them.
set_clock_groups -asynchronous -group {clk_core} -group {chip_tx_clk}

derive_clock_uncertainty

set_false_path -from [get_ports {KEY[*] SW[*]}]
set_false_path -to   [get_ports {LEDR[*] HEX*[*]}]
