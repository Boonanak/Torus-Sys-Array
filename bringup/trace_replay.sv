// trace_replay.sv  --  synthesizable trace player with stop-on-error
//
// Same opcodes as bsg_fsb_node_trace_replay (each ROM word = {4-bit op, ring_width_p data}):
//   0 nop           1 send data        2 receive and check data
//   3 done          4 finish (treated exactly like done: hardware has no $finish)
//   5 cycle-dec     6 cycle-init
//
// What is different from the old module
//   * A receive MISMATCH no longer advances: the player freezes ON that line, so the
//     address output (rom_addr_o) tells you which line failed, and err_got_o / err_exp_o
//     hold what arrived and what was expected.
//   * DONE no longer advances: the address stays on the DONE line (last line index).
//   * Optional run-off protection (rom_len_p): if the address reaches rom_len_p without
//     hitting DONE, the player freezes and raises overrun_o instead of reading garbage.
//   * Optional timeout (timeout_cycles_p): waiting too long on one send/receive freezes
//     the player and raises timeout_o.
//   * halt_i freezes the player from outside (wire one player's error into the other).
//   * After a failure, receive keeps ACCEPTING and discarding flits when
//     drain_after_error_p = 1, so the chip does not stall and the UART still logs them.
//
// All status flags are sticky until reset_i. error_o = mismatch | timeout | overrun.
module trace_replay
  #(parameter ring_width_p        = 80
   ,parameter rom_addr_width_p    = 6
   ,parameter counter_width_p     = (ring_width_p < 16) ? ring_width_p : 16
   ,parameter rom_len_p           = 0     // number of ROM lines; 0 = no run-off check
   ,parameter timeout_cycles_p    = 0     // max cycles stuck on one send/receive; 0 = never
   ,parameter drain_after_error_p = 1
   )
  (input  clk_i
  ,input  reset_i
  ,input  en_i
  ,input  halt_i

  // input channel (receive side)
  ,input  v_i
  ,input  [ring_width_p-1:0] data_i
  ,output logic ready_o

  // output channel (send side)
  ,output logic v_o
  ,output logic [ring_width_p-1:0] data_o
  ,input  yumi_i

  // ROM (asynchronous read)
  ,output [rom_addr_width_p-1:0] rom_addr_o
  ,input  [ring_width_p+4-1:0]   rom_data_i

  // status
  ,output logic done_o
  ,output logic error_o
  ,output logic mismatch_o
  ,output logic timeout_o
  ,output logic overrun_o
  ,output logic [ring_width_p-1:0] err_got_o
  ,output logic [ring_width_p-1:0] err_exp_o
  );

  typedef enum logic [3:0] {
      eNop=4'd0, eSend=4'd1, eReceive=4'd2, eDone=4'd3,
      eFinish=4'd4, eCycleDec=4'd5, eCycleInit=4'd6
  } eOp;

  logic [counter_width_p-1:0]  cycle_ctr_r, cycle_ctr_n;
  logic [rom_addr_width_p-1:0] addr_r, addr_n;
  logic                        done_r, done_n;
  logic                        mismatch_r, timeout_r, overrun_r;
  logic [ring_width_p-1:0]     got_r, exp_r;
  logic [31:0]                 stall_r;

  wire [3:0] op = rom_data_i[ring_width_p +: 4];

  wire failed   = mismatch_r | timeout_r | overrun_r;
  wire in_range = (rom_len_p == 0) || (addr_r < rom_len_p);
  wire active   = en_i & ~halt_i & ~reset_i & ~done_r & ~failed;

  assign rom_addr_o = addr_r;
  assign data_o     = rom_data_i[0 +: ring_width_p];
  assign done_o     = done_r;
  assign mismatch_o = mismatch_r;
  assign timeout_o  = timeout_r;
  assign overrun_o  = overrun_r;
  assign error_o    = failed;
  assign err_got_o  = got_r;
  assign err_exp_o  = exp_r;

  logic instr_completed;
  logic mismatch_now;

  always_comb begin
    v_o             = 1'b0;
    ready_o         = done_r | (failed & (drain_after_error_p != 0));
    done_n          = done_r;
    instr_completed = 1'b0;
    mismatch_now    = 1'b0;
    cycle_ctr_n     = cycle_ctr_r;

    if (active && in_range) begin
      case (op)
        eNop: instr_completed = 1'b1;
        eSend: begin
          v_o = 1'b1;
          if (yumi_i) instr_completed = 1'b1;
        end
        eReceive: begin
          ready_o = 1'b1;
          if (v_i) begin
            if (data_i != data_o) mismatch_now    = 1'b1;   // stay on this line
            else                  instr_completed = 1'b1;
          end
        end
        eDone, eFinish: done_n = 1'b1;                       // stay on this line
        eCycleDec: begin
          cycle_ctr_n     = cycle_ctr_r - 1'b1;
          instr_completed = ~(|cycle_ctr_r);
        end
        eCycleInit: begin
          cycle_ctr_n     = rom_data_i[counter_width_p-1:0];
          instr_completed = 1'b1;
        end
        default: begin end
      endcase
    end
  end

  assign addr_n = instr_completed ? (addr_r + 1'b1) : addr_r;

  // blocked on a send/receive that has not completed this cycle
  wire waiting = active & in_range & ((op == eSend) | (op == eReceive))
                 & ~instr_completed & ~mismatch_now;

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      addr_r      <= '0;
      done_r      <= 1'b0;
      mismatch_r  <= 1'b0;
      timeout_r   <= 1'b0;
      overrun_r   <= 1'b0;
      cycle_ctr_r <= 'd1;
      got_r       <= '0;
      exp_r       <= '0;
      stall_r     <= '0;
    end else begin
      addr_r      <= addr_n;
      done_r      <= done_n;
      cycle_ctr_r <= cycle_ctr_n;

      if (mismatch_now) begin
        mismatch_r <= 1'b1;
        got_r      <= data_i;
        exp_r      <= data_o;
      end

      if (en_i && !halt_i && !done_r && !failed && !in_range)
        overrun_r <= 1'b1;

      if (waiting) begin
        stall_r <= stall_r + 1'b1;
        if (timeout_cycles_p != 0 && stall_r >= timeout_cycles_p - 1)
          timeout_r <= 1'b1;
      end else begin
        stall_r <= '0;
      end
    end
  end

endmodule