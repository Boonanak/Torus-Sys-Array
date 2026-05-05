/*
  Upstream Wrapper
  Combines: Depacketizer (128 -> 32) + DDR Upstream PHY
*/

`include "bsg_defines.sv"

module upstream_wrapper
#(
  parameter packet_width_p = 128
  , parameter flit_width_p = 32
  , parameter fifo_els_p   = 4
  
  , parameter channel_width_p = 16
  , parameter num_channels_p  = 1
) (
  // Core
  input                            core_clk_i
  , input                          core_reset_i
  
  , input [packet_width_p-1:0]     packet_i
  , input                          valid_i
  , input [1:0]                    packet_size_i                     
  , output                         ready_o

  // IO
  , input                          io_clk_i
  , input                          io_link_reset_i
  , input                          async_token_reset_i
  
  , output [num_channels_p-1:0]    io_clk_r_o
  , output [num_channels_p-1:0][channel_width_p-1:0] io_data_r_o
  , output [num_channels_p-1:0]    io_valid_r_o
  , input  [num_channels_p-1:0]    token_clk_i
);

  logic [flit_width_p-1:0] flit_lo;
  logic                    flit_valid_lo;
  logic                    flit_ready_li;

  // --- Depacketizer Instance ---
  // Converts 128-bit memory lines into 32-bit flits
  depacketizer #(
    .packet_width_p(packet_width_p)
    ,.flit_width_p (flit_width_p)
    ,.fifo_els_p   (fifo_els_p)
  ) dpak (
    .clk_i      (core_clk_i)
    ,.reset_i    (core_reset_i)

    ,.packet_i   (packet_i)
    ,.valid_i    (valid_i)
    ,.packet_size_i (packet_size_i)
    ,.ready_o    (ready_o)

    ,.flit_o     (flit_lo)
    ,.valid_o    (flit_valid_lo)
    ,.ready_i    (flit_ready_li)
  );

  // --- DDR Upstream Instance ---
  // Takes the 32-bit flits and sends them out the DDR pins
  bsg_link_ddr_upstream #(
    .width_p           (flit_width_p)
    ,.channel_width_p   (channel_width_p)
    ,.num_channels_p    (num_channels_p)
  ) ddr_up (
    .core_clk_i        (core_clk_i)
    ,.core_link_reset_i (core_reset_i)

    ,.core_data_i      (flit_lo)
    ,.core_valid_i     (flit_valid_lo)
    ,.core_ready_o     (flit_ready_li)

    ,.io_clk_i          (io_clk_i)
    ,.io_link_reset_i   (io_link_reset_i)
    ,.async_token_reset_i(async_token_reset_i)

    ,.io_clk_r_o        (io_clk_r_o)
    ,.io_data_r_o       (io_data_r_o)
    ,.io_valid_r_o      (io_valid_r_o)
    ,.token_clk_i       (token_clk_i)
  );

endmodule