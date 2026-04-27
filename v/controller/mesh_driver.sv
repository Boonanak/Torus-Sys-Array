
import PE_pkg::*;
import ctrl_pkg::*;

module mesh_driver #(
     parameter int DIM_p = 4
    ,parameter int IFM_W_p = 8
    ,parameter int WGT_W_p = 8
    ,parameter int PSM_W_p = 19  // match TwistPE OUTPUT_WIDTH_p for N=8
    ,localparam int CYC_W_lp = $clog2(DIM_p+1)
)(
     input  logic                              clk_i
    ,input  logic                              reset_i

    ,input  mesh_req_t                         req_i
    ,input  logic                              req_v_i
    ,output logic                              req_ready_o
    ,output logic                              done_o

    ,input  logic signed [IFM_W_p-1:0]         ifmap_row_i  [DIM_p-1:0]
    ,input  logic signed [WGT_W_p-1:0]         weight_row_i [DIM_p-1:0]
    ,input  logic signed [PSM_W_p-1:0]         bias_row_i   [DIM_p-1:0]

    ,output logic [CYC_W_lp-1:0]               cycle_o
    ,output logic                              cycle_v_o  // 1 during FIRE phase

    ,output logic signed [PSM_W_p-1:0]         psum_row_o   [DIM_p-1:0]
    ,output logic                              capture_v_o
    ,output logic [CYC_W_lp-1:0]               capture_idx_o  // 0..DIM_p-1

    ,output logic                              overflow_o

    ,output logic signed [WGT_W_p-1:0]         mesh_in_weight_o   [DIM_p-1:0]
    ,output logic                              mesh_in_lock_o     [DIM_p-1:0]
    ,output logic signed [IFM_W_p-1:0]         mesh_in_ifmap_o    [DIM_p-1:0]
    ,output logic signed [PSM_W_p-1:0]         mesh_in_psum_o     [DIM_p-1:0]
    ,output logic                              mesh_in_propagate_o
    ,output logic                              mesh_in_valid_o
    ,output logic                              mesh_in_last_o

    ,input  logic signed [PSM_W_p-1:0]         mesh_out_psum_i    [DIM_p-1:0]
    ,input  logic                              mesh_out_valid_i
    ,input  logic                              mesh_out_last_i
);

    typedef enum logic [1:0] { S_IDLE, S_FIRE, S_DRAIN, S_FINISH } state_e;
    state_e st_r, st_n;

    logic [CYC_W_lp-1:0] fire_cnt_r,    fire_cnt_n;  // 0..DIM_p-1
    logic [CYC_W_lp-1:0] drain_cnt_r,   drain_cnt_n;  // 0..DIM_p-2
    logic [CYC_W_lp-1:0] cap_cnt_r,     cap_cnt_n;  // 0..DIM_p (DIM_p=done)

    mesh_req_t           req_r,         req_n;
    logic                req_held_r,    req_held_n;

    logic                prop_r,        prop_n;  // double-buffer toggle

    assign req_ready_o = (st_r == S_IDLE);

    logic accept_now;
    assign accept_now = req_v_i & req_ready_o;

    always_comb begin
        st_n        = st_r;
        fire_cnt_n  = fire_cnt_r;
        drain_cnt_n = drain_cnt_r;
        cap_cnt_n   = cap_cnt_r;
        req_n       = req_r;
        req_held_n  = req_held_r;
        prop_n      = prop_r;

        case (st_r)
            S_IDLE: if (accept_now) begin
                req_n      = req_i;
                req_held_n = 1'b1;
                fire_cnt_n = '0;
                drain_cnt_n= '0;
                cap_cnt_n  = '0;
                if (req_i.flip_propagate) prop_n = ~prop_r;  // double-buffer flip on load
                st_n       = S_FIRE;
            end

            S_FIRE: begin
                fire_cnt_n = fire_cnt_r + 1'b1;
                if (fire_cnt_r == DIM_p[CYC_W_lp-1:0] - 1) begin
                    st_n        = S_DRAIN;
                    drain_cnt_n = '0;
                end
            end

            S_DRAIN: begin
                drain_cnt_n = drain_cnt_r + 1'b1;
                if (drain_cnt_r == DIM_p[CYC_W_lp-1:0] - 2) begin
                    st_n = S_FINISH;  // drain done; wait for capture
                end
            end

            S_FINISH: begin
                if (!req_r.do_compute || cap_cnt_r == DIM_p[CYC_W_lp-1:0]) begin
                    st_n       = S_IDLE;
                    req_held_n = 1'b0;
                end
            end

            default: st_n = S_IDLE;
        endcase

        if ((st_r == S_FIRE || st_r == S_DRAIN || st_r == S_FINISH)
              && req_r.do_compute
              && mesh_out_valid_i
              && cap_cnt_r < DIM_p[CYC_W_lp-1:0]) begin
            cap_cnt_n = cap_cnt_r + 1'b1;
        end
    end

    logic in_fire_phase;
    assign in_fire_phase = (st_r == S_FIRE);

    logic in_run_phase;
    assign in_run_phase = (st_r == S_FIRE) || (st_r == S_DRAIN);

    assign mesh_in_valid_o = in_run_phase;

    assign mesh_in_last_o = (st_r == S_DRAIN) &&
                            (drain_cnt_r == DIM_p[CYC_W_lp-1:0] - 2);

    assign mesh_in_propagate_o = prop_r;

    genvar gr;
    generate
        for (gr = 0; gr < DIM_p; gr++) begin : g_drive
            assign mesh_in_weight_o[gr] =
                (in_fire_phase && req_r.do_load_weight) ? weight_row_i[gr] : '0;

            assign mesh_in_lock_o[gr] =
                (in_fire_phase && req_r.do_load_weight
                 && fire_cnt_r == gr[CYC_W_lp-1:0]);

            assign mesh_in_ifmap_o[gr] =
                (in_fire_phase && req_r.do_compute) ? ifmap_row_i[gr] : '0;

            assign mesh_in_psum_o[gr] =
                (in_fire_phase && req_r.do_compute) ? bias_row_i[gr] : '0;
        end
    endgenerate

    assign capture_v_o   = req_r.do_compute &&
                           (st_r == S_FIRE || st_r == S_DRAIN ||
                            st_r == S_FINISH) &&
                           mesh_out_valid_i &&
                           (cap_cnt_r < DIM_p[CYC_W_lp-1:0]);
    assign capture_idx_o = cap_cnt_r;
    generate
        for (gr = 0; gr < DIM_p; gr++) begin : g_cap
            assign psum_row_o[gr] = mesh_out_psum_i[gr];
        end
    endgenerate

    logic overflow_pulse;
    always_comb begin
        overflow_pulse = 1'b0;
        if (capture_v_o) begin
            for (int rr = 0; rr < DIM_p; rr++) begin
                if (mesh_out_psum_i[rr] == '1 ||  // detect saturation crudely
                    mesh_out_psum_i[rr] == {1'b1,{(PSM_W_p-1){1'b0}}}) begin
                    overflow_pulse = 1'b1;
                end
            end
        end
    end
    assign overflow_o = overflow_pulse;

    assign cycle_o   = fire_cnt_r;
    assign cycle_v_o = in_fire_phase;

    assign done_o = (st_r == S_FINISH) && (st_n == S_IDLE);

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            st_r        <= S_IDLE;
            fire_cnt_r  <= '0;
            drain_cnt_r <= '0;
            cap_cnt_r   <= '0;
            req_r       <= '0;
            req_held_r  <= 1'b0;
            prop_r      <= 1'b0;
        end else begin
            st_r        <= st_n;
            fire_cnt_r  <= fire_cnt_n;
            drain_cnt_r <= drain_cnt_n;
            cap_cnt_r   <= cap_cnt_n;
            req_r       <= req_n;
            req_held_r  <= req_held_n;
            prop_r      <= prop_n;
        end
    end

endmodule
