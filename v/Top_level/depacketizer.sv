/*
Inputs:
 clk_i: core clock
 reset_i: core reset
 packet_i (from mem): The complete line (or packet) from memory
 valid_i (from mem): Valid packet data
 ready_i (to upstream): bsg_link_upstream is ready for more data
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
) (
  input                        clk_i
  , input                      reset_i

  // Input from Memory
  , input [packet_width_p-1:0] packet_i
  , input                      valid_i
  , output logic               ready_o

  // Output to bsg_upstream
  , output [flit_width_p-1:0]  flit_o
  , output                     valid_o
  , input                      ready_i
);

  localparam num_flits_lp = packet_width_p / flit_width_p;

  // How many bits the counter needs
  logic [$clog2(num_flits_lp)-1:0] flit_cnt_r, flit_cnt_n;
  logic [packet_width_p-1:0] packet_r;
  logic packet_v_r, packet_v_n;
  
  logic fifo_ready_lo;
  logic [flit_width_p-1:0] flit_mux_lo;
  logic flit_valid_lo;

  // --- Control Logic ---
  // We only accept a new packet when the current one is finished 
  // and the FIFO has room to start the sequence.
  // Is driven explicitly (not just passed in to something) which is why it has to be "logic"
  assign ready_o = (flit_cnt_r == '0) && !packet_v_r;

  always_comb begin
    flit_cnt_n    = flit_cnt_r;
    packet_v_n    = packet_v_r;
    flit_valid_lo = 1'b0;

    if (packet_v_r) begin
      flit_valid_lo = 1'b1;
      if (fifo_ready_lo) begin
        flit_cnt_n = flit_cnt_r + 1'b1;
        // After 4th flit (11 -> 00), clear the current packet
        if (flit_cnt_r == (num_flits_lp - 1)) begin
          packet_v_n = 1'b0;
        end
      end
    end else if (valid_i && ready_o) begin
      packet_v_n = 1'b1;
      flit_cnt_n = '0;
    end
  end

  // --- Big Endian Mux: 127:96, then 95:64, etc. ---
  // Using flit_cnt_r to select the slice
  // Ex: flit_cnt_r - 0 and flit_width_p = 32
  // packet_r[(3 - 0) * 32 +: 32] = packet_r[96 +: 32] ... [127:96]
  assign flit_mux_lo = packet_r[((num_flits_lp - 1) - flit_cnt_r)*flit_width_p +: flit_width_p];

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      flit_cnt_r <= '0;
      packet_v_r <= 1'b0;
      packet_r   <= '0;
    end else begin
      flit_cnt_r <= flit_cnt_n;
      packet_v_r <= packet_v_n;
      if (ready_o && valid_i) begin
        packet_r <= packet_i;
      end
    end
  end

  // --- Output Skid/Sync FIFO ---
  // 4-element deep so it can hold 1 complete packet (line from memory) at a time
  bsg_fifo_1r1w_small #(
    .width_p(flit_width_p)
    ,.els_p(fifo_els_p)
  ) out_fifo (
    .clk_i   (clk_i)
    ,.reset_i (reset_i)

    ,.data_i  (flit_mux_lo)
    ,.v_i     (flit_valid_lo)
    ,.ready_o (fifo_ready_lo)

    ,.data_o  (flit_o)
    ,.v_o     (valid_o)
    ,.yumi_i  (valid_o & ready_i)
  );

endmodule