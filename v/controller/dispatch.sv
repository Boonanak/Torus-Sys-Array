
import ctrl_pkg::*;

module dispatch (
     input  logic          clk_i
    ,input  logic          reset_i

    ,input  decoded_cmd_t  cmd_i
    ,input  logic          cmd_v_i
    ,output logic          cmd_ready_o

    ,output decoded_cmd_t  wr_cmd_o
    ,output logic          wr_v_o
    ,input  logic          wr_ready_i
    ,input  logic          wr_done_i

    ,output decoded_cmd_t  rd_cmd_o
    ,output logic          rd_v_o
    ,input  logic          rd_ready_i
    ,input  logic          rd_done_i

    ,output decoded_cmd_t  ex_cmd_o
    ,output logic          ex_v_o
    ,input  logic          ex_ready_i
    ,input  logic          ex_done_i

    ,output decoded_cmd_t  cs_cmd_o
    ,output logic          cs_v_o
    ,input  logic          cs_ready_i
    ,input  logic          cs_done_i
);

    logic is_wr, is_rd, is_ex, is_cs;
    always_comb begin
        is_wr = 1'b0; is_rd = 1'b0; is_ex = 1'b0; is_cs = 1'b0;
        unique case (cmd_i.op)
            OP_WRITE:                                           is_wr=1;
            OP_READV8, OP_READV16, OP_READM8, OP_READM16:       is_rd=1;
            OP_LR,  OP_LC,
            OP_CR,  OP_CC,
            OP_LRCR,OP_LCCR,OP_LRCC,OP_LCCC,
            OP_TRANSPOSE:                                       is_ex=1;
            OP_NOOP, OP_READ_CSR, OP_WRITE_CSR, OP_ERROR_CSR:   is_cs=1;
            default:                                            is_cs=1;  // unknown → csr handles INVALID flag
        endcase
    end

    logic inflight_r, inflight_n;
    logic [1:0] tgt_r, tgt_n;
    localparam bit [1:0] T_WR=2'd0, T_RD=2'd1, T_EX=2'd2, T_CS=2'd3;

    logic accept_now;
    assign accept_now = cmd_v_i && !inflight_r &&
                        ( (is_wr & wr_ready_i) |
                          (is_rd & rd_ready_i) |
                          (is_ex & ex_ready_i) |
                          (is_cs & cs_ready_i) );

    logic done_now;
    assign done_now = inflight_r && (
                     (tgt_r == T_WR & wr_done_i) |
                     (tgt_r == T_RD & rd_done_i) |
                     (tgt_r == T_EX & ex_done_i) |
                     (tgt_r == T_CS & cs_done_i) );

    always_comb begin
        inflight_n = inflight_r;
        tgt_n      = tgt_r;
        if (accept_now) begin
            inflight_n = 1'b1;
            tgt_n      = is_wr ? T_WR : is_rd ? T_RD :
                         is_ex ? T_EX : T_CS;
        end
        if (done_now) inflight_n = 1'b0;
    end

    assign wr_v_o    = accept_now & is_wr;
    assign rd_v_o    = accept_now & is_rd;
    assign ex_v_o    = accept_now & is_ex;
    assign cs_v_o    = accept_now & is_cs;
    assign wr_cmd_o  = cmd_i;
    assign rd_cmd_o  = cmd_i;
    assign ex_cmd_o  = cmd_i;
    assign cs_cmd_o  = cmd_i;

    assign cmd_ready_o = done_now;

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            inflight_r <= 1'b0;
            tgt_r      <= T_WR;
        end else begin
            inflight_r <= inflight_n;
            tgt_r      <= tgt_n;
        end
    end

endmodule
