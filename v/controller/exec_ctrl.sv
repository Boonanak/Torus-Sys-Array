
import ctrl_pkg::*;
import scratchpad_pkg::*;

module exec_ctrl #(
     parameter int DIM_p = scratchpad_pkg::DIM_p
    ,parameter int NUM_MATRICES_p = scratchpad_pkg::NUM_MATRICES_p
    ,localparam int IFM_W_lp = DIM_p * 8
    ,localparam int WGT_W_lp = DIM_p * 8
    ,localparam int PSM_W_lp = DIM_p * 32  // bank-side; sign-ext 16→19 for mesh, truncate 19→16 on writeback
    ,localparam int ADDR_W_lp = $clog2(NUM_MATRICES_p * DIM_p)
    ,localparam int CYC_W_lp  = $clog2(DIM_p+1)
)(
     input  logic          clk_i
    ,input  logic          reset_i

    ,input  decoded_cmd_t  cmd_i
    ,input  logic          v_i
    ,output logic          ready_o
    ,output logic          done_o

    ,output logic          ex_active_o

    ,output logic                       ifm_r_v_o
    ,output logic [ADDR_W_lp-1:0]       ifm_r_addr_o
    ,input  logic [IFM_W_lp-1:0]        ifm_r_data_i
    ,output logic                       wgt_r_v_o
    ,output logic [ADDR_W_lp-1:0]       wgt_r_addr_o
    ,input  logic [WGT_W_lp-1:0]        wgt_r_data_i
    ,output logic                       psm_r_v_o
    ,output logic [ADDR_W_lp-1:0]       psm_r_addr_o
    ,input  logic [PSM_W_lp-1:0]        psm_r_data_i

    ,output logic                       psm_w_v_o
    ,output logic [ADDR_W_lp-1:0]       psm_w_addr_o
    ,output logic [PSM_W_lp-1:0]        psm_w_data_o

    ,output logic                       ifm_w_v_o
    ,output logic [ADDR_W_lp-1:0]       ifm_w_addr_o
    ,output logic [IFM_W_lp-1:0]        ifm_w_data_o

    ,output mesh_req_t                  mreq_o
    ,output logic                       mreq_v_o
    ,input  logic                       mreq_ready_i
    ,input  logic                       mreq_done_i

    ,output logic signed [7:0]          mesh_ifmap_row_o [DIM_p-1:0]
    ,output logic signed [7:0]          mesh_weight_row_o [DIM_p-1:0]
    ,output logic signed [18:0]         mesh_bias_row_o [DIM_p-1:0]
    ,input  logic [CYC_W_lp-1:0]        mesh_cycle_i
    ,input  logic                       mesh_cycle_v_i

    ,input  logic signed [18:0]         mesh_psum_row_i  [DIM_p-1:0]
    ,input  logic                       mesh_capture_v_i
    ,input  logic [CYC_W_lp-1:0]        mesh_capture_idx_i

    ,output logic signed [7:0]          tp_in_data_o   [DIM_p-1:0]
    ,output logic                       tp_in_valid_o
    ,output logic                       tp_transpose_o
    ,output logic                       tp_out_ready_o
    ,input  logic                       tp_in_ready_i
    ,input  logic                       tp_out_valid_i
    ,input  logic signed [7:0]          tp_out_data_i  [DIM_p-1:0]

    ,output logic                       transpose_conflict_o
);

    logic do_compute, do_load_w, a_trans, d_trans, is_transpose;
    always_comb begin
        do_compute   = 1'b0; do_load_w = 1'b0;
        a_trans      = 1'b0; d_trans   = 1'b0;
        is_transpose = 1'b0;
        unique case (cmd_i.op)
            OP_LR:    begin do_load_w=1; d_trans=1; end  // Load Row-major
            OP_LC:    begin do_load_w=1; d_trans=0; end  // Load Col-major
            OP_CR:    begin do_compute=1; a_trans=1; end  // Compute Row-major A
            OP_CC:    begin do_compute=1; a_trans=0; end  // Compute Col-major A
            OP_LRCR:  begin do_compute=1; do_load_w=1; a_trans=1; d_trans=1; end  // both need TP → CONFLICT
            OP_LCCR:  begin do_compute=1; do_load_w=1; a_trans=1; d_trans=0; end
            OP_LRCC:  begin do_compute=1; do_load_w=1; a_trans=0; d_trans=1; end
            OP_LCCC:  begin do_compute=1; do_load_w=1; a_trans=0; d_trans=0; end
            OP_TRANSPOSE: is_transpose = 1'b1;
            default: ;
        endcase
    end

    assign transpose_conflict_o = v_i & a_trans & d_trans;

    logic use_tp, tp_for_a;
    assign use_tp   = a_trans | d_trans;
    assign tp_for_a = a_trans;  // A wins on conflict

    typedef enum logic [2:0] {
        S_IDLE,
        S_TP_PRIME,        // pre-fill transposer for compute
        S_FIRE,            // mreq sent, mesh runs
        S_TP_OP_PRIME,     // TRANSPOSE: pump src into TP
        S_TP_OP_DRAIN,     // TRANSPOSE: drain TP, write dst
        S_DONE
    } st_e;
    st_e st_r, st_n;

    decoded_cmd_t cmd_r, cmd_n;
    logic do_compute_r, do_load_w_r, a_trans_r, d_trans_r;
    logic is_transpose_r, use_tp_r, tp_for_a_r;

    logic [CYC_W_lp-1:0] prime_cnt_r, prime_cnt_n;
    logic [CYC_W_lp-1:0] tpop_drain_cnt_r, tpop_drain_cnt_n;

    assign ready_o = (st_r == S_IDLE);

    logic accept_now;
    assign accept_now = v_i & ready_o & mreq_ready_i;

    always_comb begin
        st_n             = st_r;
        cmd_n            = cmd_r;
        prime_cnt_n      = prime_cnt_r;
        tpop_drain_cnt_n = tpop_drain_cnt_r;

        case (st_r)
            S_IDLE: if (accept_now) begin
                cmd_n       = cmd_i;
                prime_cnt_n = '0;
                tpop_drain_cnt_n = '0;
                if      (is_transpose) st_n = S_TP_OP_PRIME;
                else if (use_tp)       st_n = S_TP_PRIME;
                else                    st_n = S_FIRE;
            end

            S_TP_PRIME: begin
                prime_cnt_n = prime_cnt_r + 1;
                if (prime_cnt_r == DIM_p[CYC_W_lp-1:0] - 1) begin
                    st_n = S_FIRE;
                end
            end

            S_FIRE: if (mreq_done_i) begin
                st_n = S_DONE;
            end

            S_TP_OP_PRIME: begin
                prime_cnt_n = prime_cnt_r + 1;
                if (prime_cnt_r == DIM_p[CYC_W_lp-1:0] - 1) begin
                    st_n             = S_TP_OP_DRAIN;
                    tpop_drain_cnt_n = '0;
                end
            end

            S_TP_OP_DRAIN: begin
                if (tp_out_valid_i) tpop_drain_cnt_n = tpop_drain_cnt_r + 1;
                if (tpop_drain_cnt_r == DIM_p[CYC_W_lp-1:0] - 1
                    && tp_out_valid_i) st_n = S_DONE;
            end

            S_DONE: st_n = S_IDLE;

            default: st_n = S_IDLE;
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            st_r           <= S_IDLE;
            cmd_r          <= '0;
            prime_cnt_r    <= '0;
            tpop_drain_cnt_r <= '0;
            do_compute_r   <= 1'b0; do_load_w_r <= 1'b0;
            a_trans_r      <= 1'b0; d_trans_r   <= 1'b0;
            is_transpose_r <= 1'b0;
            use_tp_r       <= 1'b0; tp_for_a_r  <= 1'b0;
        end else begin
            st_r           <= st_n;
            cmd_r          <= cmd_n;
            prime_cnt_r    <= prime_cnt_n;
            tpop_drain_cnt_r <= tpop_drain_cnt_n;
            if (accept_now) begin
                do_compute_r   <= do_compute;
                do_load_w_r    <= do_load_w;
                a_trans_r      <= a_trans;
                d_trans_r      <= d_trans;
                is_transpose_r <= is_transpose;
                use_tp_r       <= use_tp;
                tp_for_a_r     <= tp_for_a;
            end
        end
    end

    logic mreq_v_q;
    always_ff @(posedge clk_i) begin
        if (reset_i) mreq_v_q <= 1'b0;
        else         mreq_v_q <= (st_n == S_FIRE) && (st_r != S_FIRE);
    end
    assign mreq_v_o = mreq_v_q;

    always_comb begin
        mreq_o                = '0;
        mreq_o.do_compute     = do_compute_r;
        mreq_o.do_load_weight = do_load_w_r;
        mreq_o.flip_propagate = do_load_w_r;
        mreq_o.src_a_base     = cmd_r.baddr_src;
        mreq_o.src_bias_base  = cmd_r.baddr_acc;
        mreq_o.src_wgt_base   = cmd_r.baddr_weight;
        mreq_o.dst_base       = cmd_r.baddr_dest;
        mreq_o.a_transpose    = a_trans_r;
        mreq_o.d_transpose    = d_trans_r;
    end

    assign ex_active_o = (st_r != S_IDLE) && (st_r != S_DONE);

    function automatic logic [ADDR_W_lp-1:0]
            row_addr(input logic [5:0] base, input logic [CYC_W_lp-1:0] k);
        return base * DIM_p + k;
    endfunction

    always_comb begin
        ifm_r_v_o    = 1'b0;
        ifm_r_addr_o = '0;
        if (st_r == S_TP_PRIME && tp_for_a_r) begin
            ifm_r_v_o    = 1'b1;
            ifm_r_addr_o = row_addr(cmd_r.baddr_src, prime_cnt_r);
        end else if (st_r == S_FIRE && do_compute_r && !a_trans_r) begin
            ifm_r_v_o    = mesh_cycle_v_i;
            ifm_r_addr_o = row_addr(cmd_r.baddr_src, mesh_cycle_i);
        end else if (st_r == S_TP_OP_PRIME) begin
            ifm_r_v_o    = 1'b1;
            ifm_r_addr_o = row_addr(cmd_r.baddr_src, prime_cnt_r);
        end
    end

    always_comb begin
        wgt_r_v_o    = 1'b0;
        wgt_r_addr_o = '0;
        if (st_r == S_TP_PRIME && !tp_for_a_r) begin
            wgt_r_v_o    = 1'b1;
            wgt_r_addr_o = row_addr(cmd_r.baddr_weight, prime_cnt_r);
        end else if (st_r == S_FIRE && do_load_w_r && !d_trans_r) begin
            wgt_r_v_o    = mesh_cycle_v_i;
            wgt_r_addr_o = row_addr(cmd_r.baddr_weight, mesh_cycle_i);
        end
    end

    always_comb begin
        psm_r_v_o    = 1'b0;
        psm_r_addr_o = '0;
        if (st_r == S_FIRE && do_compute_r) begin
            psm_r_v_o    = mesh_cycle_v_i;
            psm_r_addr_o = row_addr(cmd_r.baddr_acc, mesh_cycle_i);
        end
    end

    always_comb begin
        for (int gr = 0; gr < DIM_p; gr++) tp_in_data_o[gr] = '0;
        if (st_r == S_TP_PRIME || st_r == S_TP_OP_PRIME) begin
            if (tp_for_a_r || st_r == S_TP_OP_PRIME) begin
                for (int gr = 0; gr < DIM_p; gr++)
                    tp_in_data_o[gr] = ifm_r_data_i[gr*8 +: 8];
            end else begin
                for (int gr = 0; gr < DIM_p; gr++)
                    tp_in_data_o[gr] = wgt_r_data_i[gr*8 +: 8];
            end
        end
    end

    assign tp_in_valid_o  = (st_r == S_TP_PRIME) || (st_r == S_TP_OP_PRIME);
    assign tp_transpose_o = use_tp_r | is_transpose_r;  // ON during prime+fire/drain
    assign tp_out_ready_o = ((st_r == S_FIRE) && mesh_cycle_v_i)  // mesh in S_FIRE consuming
                          || (st_r == S_TP_OP_DRAIN);  // TRANSPOSE drains 1/cyc

    genvar gr2;
    generate
        for (gr2 = 0; gr2 < DIM_p; gr2++) begin : g_mesh_mux
            assign mesh_ifmap_row_o[gr2]  =
                a_trans_r ? tp_out_data_i[gr2] : ifm_r_data_i[gr2*8 +: 8];
            assign mesh_weight_row_o[gr2] =
                (d_trans_r && !tp_for_a_r) ? tp_out_data_i[gr2]
                                            : wgt_r_data_i[gr2*8 +: 8];
            assign mesh_bias_row_o[gr2]   =
                {{3{psm_r_data_i[gr2*16+15]}}, psm_r_data_i[gr2*16 +: 16]};
        end
    endgenerate

    assign psm_w_v_o    = mesh_capture_v_i;
    assign psm_w_addr_o = row_addr(cmd_r.baddr_dest, mesh_capture_idx_i);
    always_comb begin
        psm_w_data_o = '0;
        for (int rr = 0; rr < DIM_p; rr++) begin
            psm_w_data_o[rr*16 +: 16] = mesh_psum_row_i[rr][15:0];
        end
    end

    assign ifm_w_v_o    = (st_r == S_TP_OP_DRAIN) && tp_out_valid_i;
    assign ifm_w_addr_o = row_addr(cmd_r.baddr_dest, tpop_drain_cnt_r);
    always_comb begin
        ifm_w_data_o = '0;
        for (int rr = 0; rr < DIM_p; rr++) begin
            ifm_w_data_o[rr*8 +: 8] = tp_out_data_i[rr];
        end
    end

    assign done_o = (st_r == S_DONE);

endmodule
