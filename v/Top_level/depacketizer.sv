/*
Inputs:
  clk_i: core clock
  reset_i: core reset
  packet_i (from mem): The complete line (or packet) from memory
  valid_i (from mem): Valid packet data
  ready_i (to upstream): bsg_link_upstream is ready for more data
  packet_size_i (from mem): Which flits are actually valid in the 128 bit block
    Size 1: Stop when cnt is 0 (Three bottom flits are 0)
    Size 2: Stop when cnt is 1 (Two bottom flits are 0)
    Size 3: Stop when cnt is 2 (One bottom flit is 0)
    Size 4 (or 0): Stop when cnt is 3 (Full packet)
Outputs:
  ready_o: (from mem): depacketizer is ready for more data
  flit_o (to upstream): Outputted flit to bsg_link_upstream
  valid_o (to upstream): Valid flit data
Params:
  packet_width_p: packet width parameter
  flit_width_p: fifo width parameter
  fifo_els_p: fifo depth parameter
Description: 
  depacketizer module that is used to get lines of input (128 bit) from memory, break them into
  flits (32 bit) and then send said flits to the bsg_link_upstream terminal to be sent out of
  the chip. Includes a fifo to just hold qunatities before sending them out.
*/
module depacketizer 
#(
    parameter packet_width_p = 128
  , parameter flit_width_p = 32
  , parameter fifo_els_p   = 4
  , localparam num_flits_lp = packet_width_p / flit_width_p
  , localparam flit_cnt_width_lp = $clog2(num_flits_lp) + 1
) (
  input                                clk_i
  , input                              reset_i

  // Input from Memory
  , input [packet_width_p-1:0]         packet_i
  , input                              valid_i
  , input [1:0]                        packet_size_i
  , output logic                       ready_o

  // Output to bsg_upstream
  , output [flit_cnt_width_lp-1:0]     flit_o
  , output                             valid_o
  , input                              ready_i
);

  

  logic [flit_cnt_width_lp-1:0] packet_size_r, packet_size_n;
  logic [flit_cnt_width_lp-1:0] flit_cnt_r, flit_cnt_n;
  logic [packet_width_p-1:0] packet_r, packet_n;

  assign ready_o = (flit_cnt_r >= packet_size_r);
  // assign ready_o = 1'b1; // --> this is if we want the ready_o signal to be accurate and not just a warning
  assign valid_o = (flit_cnt_r < packet_size_r);
  assign flit_o = packet_r[((num_flits_lp - 1) - flit_cnt_r) * flit_width_p +: flit_width_p];

  always_comb begin 
    packet_n = packet_r;
    flit_cnt_n = flit_cnt_r;
    packet_size_n = packet_size_r;

    if (valid_i) begin // new packet 
      packet_n = packet_i;
      packet_size_n = packet_size_i;
      flit_cnt_n = 0;
    end else if (valid_o && ready_i) begin // next flit
        flit_cnt_n = flit_cnt_r + 1;
    end
  end

  always_ff @(posedge clk_i) begin 
    if (reset_i) begin 
      flit_cnt_r <= '0;
      packet_r <= '0;
      packet_size_r <= '0;
    end else begin 
      flit_cnt_r <= flit_cnt_n;
      packet_r <= packet_n;
      packet_size_r <= packet_size_n;
    end
  end

endmodule