/*
  Upstream Wrapper
  Combines: 
    - Depacketizer (128 -> 32 bit conversion)
    - Parity Generators (Generates parity bits for each half-flit)
    - DDR Upstream PHY (17-bit physical channel)
*/

`include "bsg_defines.v"

module upstream_wrapper
#(
  parameter packet_width_p = 128
  , parameter flit_width_p = 32
  , parameter fifo_els_p   = 4
  
  , parameter channel_width_p = 17 // 16 bits data + 1 bit parity
  , parameter num_channels_p  = 1

  , localparam num_flits_lp = packet_width_p / flit_width_p
  , localparam flit_cnt_width_lp = $clog2(num_flits_lp) + 1
) (
  // Core Interface
  input                             core_clk_i
  , input                           core_reset_i
  
  , input [packet_width_p-1:0]      packet_i
  , input                           valid_i
  , input [flit_cnt_width_lp-1:0]   packet_size_i
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
  
  logic                    parity_low_lo;
  logic                    parity_high_lo;
  logic [33:0]             ddr_data_li; 

  // --- Depacketizer Instance ---
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

  // --- Dual Parity Generation ---
  
  // Parity for the first half-flit [15:0] (Rising Edge Slice)
  parity_generator #(.WIDTH_p(16)) pg_low (
      .bits_i(flit_lo[15:0])
      ,.parity_o(parity_low_lo)
  );

  // Parity for the second half-flit [31:16] (Falling Edge Slice)
  parity_generator #(.WIDTH_p(16)) pg_high (
      .bits_i(flit_lo[31:16])
      ,.parity_o(parity_high_lo)
  );

  // --- Link Mapping (34-bit SDR to 17-bit DDR) ---
  // Slice 0 (Rising): [16] = Parity Low,  [15:0]  = Data Low
  // Slice 1 (Falling):[33] = Parity High, [32:17] = Data High
  assign ddr_data_li = {
      parity_high_lo,   // Bit 33
      flit_lo[31:16],   // Bits 32:17
      parity_low_lo,    // Bit 16
      flit_lo[15:0]     // Bits 15:0
  };

  // --- DDR Upstream Instance ---
  bsg_link_ddr_upstream #(
    .width_p           (34) 
    ,.channel_width_p   (channel_width_p)
    ,.num_channels_p    (num_channels_p)
    ,.lg_credit_to_token_decimation(0)
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