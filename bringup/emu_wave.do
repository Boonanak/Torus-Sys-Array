onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -label LEDR -expand /emu_top_tb/LEDR
add wave -noupdate -label HEX5 /emu_top_tb/dut/HEX5
add wave -noupdate -label HEX4 /emu_top_tb/dut/HEX4
add wave -noupdate -label HEX3 /emu_top_tb/dut/HEX3
add wave -noupdate -label HEX2 /emu_top_tb/dut/HEX2
add wave -noupdate -label HEX1 /emu_top_tb/dut/HEX1
add wave -noupdate -label HEX0 /emu_top_tb/dut/HEX0
add wave -noupdate -label clock /emu_top_tb/dut/clk
add wave -noupdate -label reset /emu_top_tb/dut/rst
add wave -noupdate -label trace_enable /emu_top_tb/dut/run
add wave -noupdate -label core_clk /emu_top_tb/dut/u_driver/core_clk
add wave -noupdate -label hard_reset /emu_top_tb/dut/u_driver/hard_reset
add wave -noupdate -label RX_data /emu_top_tb/dut/u_driver/rx_data
add wave -noupdate -label RX_clk /emu_top_tb/dut/u_driver/rx_clk
add wave -noupdate -label RX_token /emu_top_tb/dut/u_driver/rx_token
add wave -noupdate -label RX_valid /emu_top_tb/dut/u_driver/rx_valid
add wave -noupdate -label TX_data /emu_top_tb/dut/u_driver/tx_data
add wave -noupdate -label TX_clk /emu_top_tb/dut/u_driver/tx_clk
add wave -noupdate -label TX_token /emu_top_tb/dut/u_driver/tx_token
add wave -noupdate -label TX_valid /emu_top_tb/dut/u_driver/tx_valid
add wave -noupdate -label scan_en /emu_top_tb/dut/u_driver/scan_en
add wave -noupdate -label scan_in /emu_top_tb/dut/u_driver/scan_in
add wave -noupdate -label scan_out /emu_top_tb/dut/u_driver/scan_out
add wave -noupdate -label RECV_en_i /emu_top_tb/dut/u_driver/tracer_recv/en_i
add wave -noupdate -label RECV_v_i /emu_top_tb/dut/u_driver/tracer_recv/v_i
add wave -noupdate -label RECV_data_i /emu_top_tb/dut/u_driver/tracer_recv/data_i
add wave -noupdate -label RECV_v_o /emu_top_tb/dut/u_driver/tracer_recv/v_o
add wave -noupdate -label RECV_data_o /emu_top_tb/dut/u_driver/tracer_recv/data_o
add wave -noupdate -label RECV_error_o /emu_top_tb/dut/u_driver/tracer_recv/error_o
add wave -noupdate -label RECV_done_o /emu_top_tb/dut/u_driver/tracer_recv/done_o
add wave -noupdate -label RECV_addr_r /emu_top_tb/dut/u_driver/tracer_recv/addr_r
add wave -noupdate -label SEND_done_o /emu_top_tb/dut/u_driver/tracer_send/done_o
add wave -noupdate -label SEND_error_o /emu_top_tb/dut/u_driver/tracer_send/error_o
add wave -noupdate -label SEND_addr_r /emu_top_tb/dut/u_driver/tracer_send/addr_r
add wave -noupdate -label SEND_mismatch_o /emu_top_tb/dut/u_driver/tracer_send/mismatch_o
add wave -noupdate -label SEND_timeout_o /emu_top_tb/dut/u_driver/tracer_send/timeout_o
add wave -noupdate -label SEND_overrun_o /emu_top_tb/dut/u_driver/tracer_send/overrun_o
add wave -noupdate -label SEND_in_range /emu_top_tb/dut/u_driver/tracer_send/in_range
add wave -noupdate -expand -group BSG_LINK_WRAPPER_INTERNALS /emu_top_tb/dut/u_driver/u_bsg_link_wrapper/core_clk_i
add wave -noupdate -expand -group BSG_LINK_WRAPPER_INTERNALS /emu_top_tb/dut/u_driver/u_bsg_link_wrapper/reset_i
add wave -noupdate -expand -group BSG_LINK_WRAPPER_INTERNALS /emu_top_tb/dut/u_driver/u_bsg_link_wrapper/io_master_clk_i
add wave -noupdate -expand -group BSG_LINK_WRAPPER_INTERNALS /emu_top_tb/dut/u_driver/u_bsg_link_wrapper/upstream_io_link_reset_i
add wave -noupdate -expand -group BSG_LINK_WRAPPER_INTERNALS /emu_top_tb/dut/u_driver/u_bsg_link_wrapper/async_token_reset_i
add wave -noupdate -expand -group BSG_LINK_WRAPPER_INTERNALS /emu_top_tb/dut/u_driver/u_bsg_link_wrapper/token_clk_i
add wave -noupdate -expand -group BSG_LINK_WRAPPER_INTERNALS /emu_top_tb/dut/u_driver/u_bsg_link_wrapper/downstream_io_link_reset_i
add wave -noupdate -expand -group BSG_LINK_WRAPPER_INTERNALS /emu_top_tb/dut/u_driver/u_bsg_link_wrapper/downstream_io_clk_i
add wave -noupdate -expand -group BSG_LINK_WRAPPER_INTERNALS /emu_top_tb/dut/u_driver/u_bsg_link_wrapper/downstream_io_data_i
add wave -noupdate -expand -group BSG_LINK_WRAPPER_INTERNALS /emu_top_tb/dut/u_driver/u_bsg_link_wrapper/downstream_io_valid_i
add wave -noupdate -expand -group BSG_LINK_WRAPPER_INTERNALS /emu_top_tb/dut/u_driver/u_bsg_link_wrapper/upstream_io_clk_r_o
add wave -noupdate -expand -group BSG_LINK_WRAPPER_INTERNALS /emu_top_tb/dut/u_driver/u_bsg_link_wrapper/upstream_io_data_r_o
add wave -noupdate -expand -group BSG_LINK_WRAPPER_INTERNALS /emu_top_tb/dut/u_driver/u_bsg_link_wrapper/upstream_io_valid_r_o
add wave -noupdate -expand -group BSG_LINK_WRAPPER_INTERNALS /emu_top_tb/dut/u_driver/u_bsg_link_wrapper/downstream_core_token_r_o
add wave -noupdate -expand -group BSG_LINK_WRAPPER_INTERNALS /emu_top_tb/dut/u_driver/u_bsg_link_wrapper/rx_data_o
add wave -noupdate -expand -group BSG_LINK_WRAPPER_INTERNALS /emu_top_tb/dut/u_driver/u_bsg_link_wrapper/rx_valid_o
add wave -noupdate -expand -group BSG_LINK_WRAPPER_INTERNALS /emu_top_tb/dut/u_driver/u_bsg_link_wrapper/rx_yumi_i
add wave -noupdate -expand -group BSG_LINK_WRAPPER_INTERNALS /emu_top_tb/dut/u_driver/u_bsg_link_wrapper/tx_data_i
add wave -noupdate -expand -group BSG_LINK_WRAPPER_INTERNALS /emu_top_tb/dut/u_driver/u_bsg_link_wrapper/tx_valid_i
add wave -noupdate -expand -group BSG_LINK_WRAPPER_INTERNALS /emu_top_tb/dut/u_driver/u_bsg_link_wrapper/tx_ready_o
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {212008 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ps} {2310578 ps}
