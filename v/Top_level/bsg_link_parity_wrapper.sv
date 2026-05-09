// Integrated DDR Link Wrapper with:
//   - Dual Parity Generation/Checking (1 bit per 16-bit half-flit)
//   - 32-bit Core Interface (NO DEPACKETIZER)
//   - BaseJump STL DDR PHYs

`include "bsg_defines.v"

module bsg_link_wrapper #(
    parameter int FLIT_WIDTH    = 32,
    parameter int CHANNEL_WIDTH = 17 // 16 data + 1 parity per edge
) (
    // core domain
    input  logic                     core_clk_i,
    input  logic                     reset_i,

    // upstream / TX I/O domain (drives data toward FPGA)
    input  logic                     io_master_clk_i,
    input  logic                     upstream_io_link_reset_i,
    input  logic                     async_token_reset_i,
    input  logic                     token_clk_i,

    // downstream / RX I/O domain (data arriving from FPGA)
    input  logic                     downstream_io_link_reset_i,
    input  logic                     downstream_io_clk_i,
    input  logic [CHANNEL_WIDTH-1:0] downstream_io_data_i,
    input  logic                     downstream_io_valid_i,

    // chip pads driven by upstream link
    output logic                     upstream_io_clk_r_o,
    output logic [CHANNEL_WIDTH-1:0] upstream_io_data_r_o,
    output logic                     upstream_io_valid_r_o,

    // credit return to FPGA
    output logic                     downstream_core_token_r_o,

    // core-facing ready/valid interface
    output logic [FLIT_WIDTH-1:0]    rx_data_o,
    output logic                     rx_valid_o,
    input  logic                     rx_yumi_i,
    output logic                     rx_parity_error_o, // Added for status

    input  logic [FLIT_WIDTH-1:0]    tx_data_i,
    input  logic                     tx_valid_i,
    output logic                     tx_ready_o
);

    // Mapping: [33]=P_high, [32:17]=Data_high, [16]=P_low, [15:0]=Data_low
    logic [33:0] tx_data_combined_li;
    logic [33:0] rx_data_combined_lo;
    
    logic tx_parity_low, tx_parity_high;
    logic rx_ok_low, rx_ok_high;

    // TX PATH: Parity Generation & Upstream

    parity_generator #(.WIDTH_p(16)) pg_low (
        .bits_i(tx_data_i[15:0]),
        .parity_o(tx_parity_low)
    );

    parity_generator #(.WIDTH_p(16)) pg_high (
        .bits_i(tx_data_i[31:16]),
        .parity_o(tx_parity_high)
    );

    assign tx_data_combined_li = {
        tx_parity_high, 
        tx_data_i[31:16], 
        tx_parity_low, 
        tx_data_i[15:0]
    };

    bsg_link_ddr_upstream #(
        .width_p(34),
        .channel_width_p(CHANNEL_WIDTH),
        .num_channels_p(1),
        .lg_fifo_depth_p(6)
    ) link_tx_i (
        .core_clk_i         (core_clk_i),
        .core_link_reset_i  (reset_i),
        .core_data_i        (tx_data_combined_li),
        .core_valid_i       (tx_valid_i),
        .core_ready_o       (tx_ready_o),
        .io_clk_i           (io_master_clk_i),
        .io_link_reset_i    (upstream_io_link_reset_i),
        .async_token_reset_i(async_token_reset_i),
        .io_clk_r_o         (upstream_io_clk_r_o),
        .io_data_r_o        (upstream_io_data_r_o),
        .io_valid_r_o       (upstream_io_valid_r_o),
        .token_clk_i        (token_clk_i)
    );

    // RX PATH: Downstream & Parity Checking

    bsg_link_ddr_downstream #(
        .width_p(34),
        .channel_width_p(CHANNEL_WIDTH),
        .num_channels_p(1),
        .lg_fifo_depth_p(6)
    ) link_rx_i (
        .core_clk_i       (core_clk_i),
        .core_link_reset_i(reset_i),
        .io_link_reset_i  (downstream_io_link_reset_i),
        .core_data_o      (rx_data_combined_lo),
        .core_valid_o     (rx_valid_o),
        .core_yumi_i      (rx_yumi_i),
        .io_clk_i         (downstream_io_clk_i),
        .io_data_i        (downstream_io_data_i),
        .io_valid_i       (downstream_io_valid_i),
        .core_token_r_o   (downstream_core_token_r_o)
    );

    parity_checker #(.WIDTH_p(16)) check_low (
        .bits_i(rx_data_combined_lo[15:0]),
        .parity_i(rx_data_combined_lo[16]),
        .is_parity_o(rx_ok_low)
    );

    parity_checker #(.WIDTH_p(16)) check_high (
        .bits_i(rx_data_combined_lo[32:17]),
        .parity_i(rx_data_combined_lo[33]),
        .is_parity_o(rx_ok_high)
    );

    // Reassemble final 32-bit flit for the core
    assign rx_data_o = {rx_data_combined_lo[32:17], rx_data_combined_lo[15:0]};
    
    // Error logic: High if valid data has bad parity in either half
    assign rx_parity_error_o = rx_valid_o && (!rx_ok_low || !rx_ok_high);

endmodule