/*
  Downstream Wrapper
  Combines:
    - DDR Downstream PHY (17-bit physical channel)
    - Parity Checkers (Validates each 16 bit half-flit)
*/

`include "bsg_defines.v"

module downstream_wrapper
#(
  parameter flit_width_p = 32
  , parameter channel_width_p = 17
  , parameter num_channels_p  = 1
) (
  // Core Interface
  input                               core_clk_i
  , input                             core_reset_i
  
  , output [flit_width_p-1:0]         flit_o         // reassembled 32b flit
  , output                            valid_o         
  , input                             ready_i         
  , output                            parity_error_o // OR'd error to controller

  // IO Interface
  , input [num_channels_p-1:0]        io_clk_i      
  , input [num_channels_p-1:0]        io_link_reset_i // Synchronous to io_clk_i
  , input [num_channels_p-1:0][channel_width_p-1:0] io_data_i
  , input [num_channels_p-1:0]        io_valid_i
  , output [num_channels_p-1:0]       token_clk_o    
);

  logic [33:0] ddr_data_lo;
  logic        phy_valid_lo;
  
  logic        ok_low, ok_high;

  // --- DDR Downstream Instance ---
  bsg_link_ddr_downstream #(
    .width_p(34)
    ,.channel_width_p(channel_width_p)
    ,.num_channels_p(num_channels_p)
    ,.lg_credit_to_token_decimation(0)
  ) ddr_down (
    .core_clk_i          (core_clk_i)
    ,.core_link_reset_i  (core_reset_i)
    ,.io_link_reset_i    (core_reset_i) // added this signal... set to core_reset_i for now but should we change?
    ,.core_data_o        (ddr_data_lo)
    ,.core_valid_o       (phy_valid_lo)
    ,.core_yumi_i        (phy_ready_li) // changed from core_ready_i to core_yumi_i
    ,.io_clk_i           (io_clk_i)
    ,.io_data_i          (io_data_i)
    ,.io_valid_i         (io_valid_i)
    ,.core_token_r_o     (token_clk_o) // changed from token_clk_r_o to core_token_r_o
  );

  // --- Parity Checkers (One per DDR Slice) ---

  // Checker for the Lower 16 bits (Rising Edge Slice)
  parity_checker #(.WIDTH_p(16)) check_low (
      .bits_i(ddr_data_lo[15:0])      // Data bits 0-15
      ,.parity_i(ddr_data_lo[16])     // Parity bit on pin 17 (Rising)
      ,.is_parity_o(ok_low)
  );

  // Checker for the Upper 16 bits (Falling Edge Slice)
  parity_checker #(.WIDTH_p(16)) check_high (
      .bits_i(ddr_data_lo[32:17])     // Data bits 16-31
      ,.parity_i(ddr_data_lo[33])     // Parity bit on pin 17 (Falling)
      ,.is_parity_o(ok_high)
  );

  // --- Reassembly & Error Logic ---

  // Combine the two halves back together
  assign flit_o = {ddr_data_lo[32:17], ddr_data_lo[15:0]};

  assign parity_error_o = phy_valid_lo && (!ok_low || !ok_high);

  assign valid_o = phy_valid_lo;

endmodule