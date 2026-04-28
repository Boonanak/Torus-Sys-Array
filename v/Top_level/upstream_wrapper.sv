/*
  Upstream Wrapper
  Combines: 
    - Depacketizer (128 -> 32 bit conversion)
    - Parity Generator (Generates bit for FPGA-side checking)
    - DDR Upstream PHY (17-bit physical channel)
*/

`include "bsg_defines.sv"

module upstream_wrapper
#(
  parameter packet_width_p = 128
  , parameter flit_width_p = 32
  , parameter fifo_els_p   = 4
  
  , parameter channel_width_p = 17 //16 + parity bit
  , parameter num_channels_p  = 1
) (
  // Core Interface
  input                             core_clk_i
  , input                           core_reset_i
  
  , input [packet_width_p-1:0]      packet_i
  , input                           valid_i
  , input [1:0]                     packet_size_i
  , output                          ready_o

  // IO Interface
  , input                           io_clk_i
  , input                           io_link_reset_i
  , input                           async_token_reset_i
  
  , output [num_channels_p-1:0]     io_clk_r_o
  , output [num_channels_p-1:0][channel_width_p-1:0] io_data_r_o
  , output [num_channels_p-1:0]     io_valid_r_o
  , input  [num_channels_p-1:0]     token_clk_i
);

  logic [flit_width_p-1:0] flit_lo;
  logic                    flit_valid_lo;
  logic                    flit_ready_li;
  
  logic                    flit_parity_bit;
  logic [33:0]             ddr_data_li; 

  // --- Depacketizer Instance ---
  // Converts 128-bit internal packets into 32-bit flits
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

  // --- Parity Generation ---
  // Generate parity for the 32b flit so the FPGA can verify it
  parity_generator #(.WIDTH_p(flit_width_p)) flit_pg (
      .bits_i(flit_lo)
      ,.parity_o(flit_parity_bit)
  );

  // [33]: Unused, [32]: Parity Bit, [31:0]: Data flit
  assign ddr_data_li = {1'b0, flit_parity_bit, flit_lo};

  // --- DDR Upstream Instance ---
  bsg_link_ddr_upstream #(
    .width_p           (34) 
    ,.channel_width_p   (channel_width_p)
    ,.num_channels_p    (num_channels_p)
  ) ddr_up (
    .core_clk_i        (core_clk_i)
    ,.core_link_reset_i (core_reset_i)

    ,.core_data_i      (ddr_data_li)
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