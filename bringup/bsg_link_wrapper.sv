// -----------------------------------------------------------------------
// bsg_link_wrapper.sv
//
// Pad-side / core-side glue around bsg_link_ddr_upstream and
// bsg_link_ddr_downstream from BaseJump STL. The wrapper exposes:
//
//   - off-chip DDR signals at the package boundary
//       (downstream_io_*  : FPGA -> ASIC)
//       (upstream_io_*    : ASIC -> FPGA)
//       (token_clk_i      : credit return clock from FPGA)
//       (downstream_core_token_r_o : credit return signal toward FPGA)
//
//   - a simple 32-bit ready/valid interface to the core (top.v)
//       (rx_data_o, rx_valid_o, rx_yumi_i)
//       (tx_data_i, tx_valid_i, tx_ready_o)
//
// Students should NOT need to edit this file. Use the rx_* / tx_* signals
// in top.v.
//
// Notes for this chip:
//   - io_master_clk_i is tied to core_clk_i in chip_top.sv (saves a pad).
//     bsg_link_ddr_upstream still has an internal CDC between core_clk_i
//     and io_clk_i; when those are the same net the CDC degenerates and
//     synthesis simplifies it.
//   - All link reset inputs (core_link_reset, upstream_io_link_reset,
//     async_token_reset, downstream_io_link_reset) are tied to a single
//     hard_reset at chip_top.sv to keep pad count down.
// -----------------------------------------------------------------------
module bsg_link_wrapper #(
    parameter int FLIT_WIDTH    = 32,
    parameter int CHANNEL_WIDTH = 16
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

    // credit return to FPGA (output of downstream credit counter)
    output logic                     downstream_core_token_r_o,

    // ----- core-facing ready/valid interface -----
    output logic [FLIT_WIDTH-1:0]    rx_data_o,
    output logic                     rx_valid_o,
    input  logic                     rx_yumi_i,

    input  logic [FLIT_WIDTH-1:0]    tx_data_i,
    input  logic                     tx_valid_i,
    output logic                     tx_ready_o
);

    bsg_link_ddr_downstream #(
        .width_p        (FLIT_WIDTH),
        .channel_width_p(CHANNEL_WIDTH),
        .num_channels_p (1),
        .lg_fifo_depth_p(6)
    ) link_rx_i (
        .core_clk_i       (core_clk_i),
        .core_link_reset_i(reset_i),
        .io_link_reset_i  (downstream_io_link_reset_i),
        .core_data_o      (rx_data_o),
        .core_valid_o     (rx_valid_o),
        .core_yumi_i      (rx_yumi_i),
        .io_clk_i         (downstream_io_clk_i),
        .io_data_i        (downstream_io_data_i),
        .io_valid_i       (downstream_io_valid_i),
        .core_token_r_o   (downstream_core_token_r_o)
    );

    bsg_link_ddr_upstream #(
        .width_p        (FLIT_WIDTH),
        .channel_width_p(CHANNEL_WIDTH),
        .num_channels_p (1),
        .lg_fifo_depth_p(6)
    ) link_tx_i (
        .core_clk_i         (core_clk_i),
        .core_link_reset_i  (reset_i),
        .core_data_i        (tx_data_i),
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

endmodule
