
import ctrl_pkg::*;

module cmd_decoder (
     input  logic                       clk_i
    ,input  logic                       reset_i

    ,input  logic [FLIT_W_p-1:0]        flit_i
    ,input  logic                       flit_v_i
    ,input  logic                       flit_parity_ok_i
    ,output logic                       flit_ready_o

    ,output decoded_cmd_t               cmd_o
    ,output logic                       cmd_v_o
    ,input  logic                       cmd_ready_i

    ,output err_pulse_t                 err_o
);

    typedef enum logic [1:0] { S_HEAD, S_DATA0, S_DATA1 } state_e;
    state_e st_r, st_n;

    decoded_cmd_t cmd_r, cmd_n;
    logic         emit_r, emit_n;
    err_pulse_t   err_n;

    opcode_e     hdr_op;
    logic [5:0]  hdr_dest, hdr_src, hdr_acc, hdr_weight;
    logic [8:0]  hdr_vaddr;

    assign hdr_op     = opcode_e'(flit_i[5:0]);
    assign hdr_dest   = flit_i[31:26];  // BaseAddr_dest
    assign hdr_src    = flit_i[25:20];  // BaseAddr_source
    assign hdr_acc    = flit_i[19:14];  // BaseAddr_acc
    assign hdr_weight = flit_i[13: 8];  // BaseAddr_weight
    logic is_writeish, is_readv;
    assign is_writeish = (hdr_op == OP_WRITE)      ||
                         (hdr_op == OP_WRITE_CSR);
    assign is_readv    = (hdr_op == OP_READV8) || (hdr_op == OP_READV16);
    assign hdr_vaddr   = is_writeish ? flit_i[31:23] :
                         is_readv    ? flit_i[25:17] : 9'd0;

    logic hdr_known;
    always_comb begin
        case (hdr_op)
            OP_NOOP, OP_READV8, OP_READM8, OP_READV16, OP_READM16,
            OP_READ_CSR, OP_WRITE, OP_WRITE_CSR, OP_TRANSPOSE,
            OP_ERROR_CSR, OP_CC, OP_CR, OP_LC, OP_LCCC, OP_LCCR,
            OP_LR, OP_LRCC, OP_LRCR:  hdr_known = 1'b1;
            default:                  hdr_known = 1'b0;
        endcase
    end

//    assign flit_ready_o = 1'b1;                                       // BUG: never back-pressures upstream — new flit overwrites cmd_n while emit_r=1 holds prior command
    assign flit_ready_o = !emit_r || cmd_ready_i;                     // T2SA-CTRL: stall upstream while a decoded cmd is held but downstream not ready, so the queued cmd is not silently overwritten

    always_comb begin
        st_n   = st_r;
        cmd_n  = cmd_r;
        emit_n = 1'b0;
        err_n  = '0;

        if (emit_r && cmd_ready_i) emit_n = 1'b0;
        else                       emit_n = emit_r;

        case (st_r)
            S_HEAD: if (flit_v_i) begin
                if (!flit_parity_ok_i) begin
                    err_n.parity_fail = 1'b1;  // drop flit
                end else if (!hdr_known) begin
                    err_n.invalid_op  = 1'b1;  // drop flit
                end else begin
                    cmd_n.op           = hdr_op;
                    cmd_n.baddr_dest   = hdr_dest;
                    cmd_n.baddr_src    = hdr_src;
                    cmd_n.baddr_acc    = hdr_acc;
                    cmd_n.baddr_weight = hdr_weight;
                    cmd_n.vaddr        = hdr_vaddr;
                    cmd_n.imm_data     = '0;
                    if (is_writeish) st_n = S_DATA0;
                    else begin
                        emit_n = 1'b1;
                        st_n   = S_HEAD;
                    end
                end
            end

            S_DATA0: if (flit_v_i) begin
                if (!flit_parity_ok_i) begin
                    err_n.parity_fail = 1'b1;
                    st_n              = S_HEAD;  // abort pending instr
                end else begin
                    cmd_n.imm_data[63:32] = flit_i;
                    st_n                  = S_DATA1;
                end
            end

            S_DATA1: if (flit_v_i) begin
                if (!flit_parity_ok_i) begin
                    err_n.parity_fail = 1'b1;
                    st_n              = S_HEAD;
                end else begin
                    cmd_n.imm_data[31:0] = flit_i;
                    emit_n                = 1'b1;
                    st_n                  = S_HEAD;
                end
            end

            default: st_n = S_HEAD;
        endcase

        if (emit_r && !cmd_ready_i) emit_n = 1'b1;
    end

    assign cmd_o   = cmd_r;
    assign cmd_v_o = emit_r;
    assign err_o   = err_n;  // 1-cycle pulses

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            st_r   <= S_HEAD;
            cmd_r  <= '0;
            emit_r <= 1'b0;
        end else begin
            st_r   <= st_n;
            cmd_r  <= cmd_n;
            emit_r <= emit_n;
        end
    end

endmodule
