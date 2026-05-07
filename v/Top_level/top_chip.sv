
import ctrl_pkg::*;
import scratchpad_pkg::*;
import PE_pkg::*;

module top_chip #(
     parameter int DIM_p                = scratchpad_pkg::DIM_p
    ,parameter int CMDQ_DEPTH_p         = 8
    ,localparam int IFM_W_lp            = scratchpad_pkg::IFM_ROW_W_lp
    ,localparam int WGT_W_lp            = scratchpad_pkg::WGT_ROW_W_lp
    ,localparam int PSM_W_lp            = scratchpad_pkg::PSM_ROW_W_lp
    ,localparam int BANK_DEPTH_IFM_lp   = scratchpad_pkg::BANK_DEPTH_IFM_lp
    ,localparam int BANK_DEPTH_PSM_lp   = scratchpad_pkg::BANK_DEPTH_PSM_lp
    ,localparam int BANK_ADDR_W_IFM_lp   = scratchpad_pkg::BANK_ADDR_W_IFM_lp
    ,localparam int BANK_ADDR_W_PSM_lp   = scratchpad_pkg::BANK_ADDR_W_PSM_lp
    ,localparam int CYC_W_lp            = $clog2(DIM_p+1)
)(
     input  logic        clk_i
    ,input  logic        reset_i

    ,input  logic [31:0] in_flit
    ,input  logic        in_flit_v
    ,input  logic        in_flit_par_ok
    ,output logic        in_flit_ready

    ,output logic        link_out_v_o
    ,output logic [31:0] link_out_data_o
    //,output logic        link_out_parity_o
    ,input  logic        link_out_yumi_i
);

    logic rst_n_i;
    assign rst_n_i = ~reset_i;  // csr.sv uses active-low

    decoded_cmd_t dec_cmd;
    logic         dec_cmd_v;
    logic         dec_cmd_ready;
    err_pulse_t   dec_err;

    cmd_decoder u_decoder (
         .clk_i, .reset_i
        ,.flit_i           (in_flit)
        ,.flit_v_i         (in_flit_v)
        ,.flit_parity_ok_i (in_flit_par_ok)
        ,.flit_ready_o     (in_flit_ready)
        ,.cmd_o            (dec_cmd)
        ,.cmd_v_o          (dec_cmd_v)
        ,.cmd_ready_i      (dec_cmd_ready)
        ,.err_o            (dec_err)
    );

    decoded_cmd_t q_cmd;
    logic         q_cmd_v, q_cmd_ready, q_empty;

    cmd_queue #(.DEPTH_p(CMDQ_DEPTH_p)) u_q (
         .clk_i, .reset_i
        ,.enq_data_i (dec_cmd)
        ,.enq_v_i    (dec_cmd_v)
        ,.enq_ready_o(dec_cmd_ready)
        ,.deq_data_o (q_cmd)
        ,.deq_v_o    (q_cmd_v)
        ,.deq_ready_i(q_cmd_ready)
        ,.empty_o    (q_empty)
    );

    decoded_cmd_t wr_cmd, rd_cmd, ex_cmd, cs_cmd;
    logic         wr_v, rd_v, ex_v, cs_v;
    logic         wr_ready, rd_ready, ex_ready, cs_ready;
    logic         wr_done,  rd_done,  ex_done,  cs_done;

    dispatch u_disp (
         .clk_i, .reset_i
        ,.cmd_i      (q_cmd)
        ,.cmd_v_i    (q_cmd_v)
        ,.cmd_ready_o(q_cmd_ready)
        ,.wr_cmd_o(wr_cmd), .wr_v_o(wr_v), .wr_ready_i(wr_ready), .wr_done_i(wr_done)
        ,.rd_cmd_o(rd_cmd), .rd_v_o(rd_v), .rd_ready_i(rd_ready), .rd_done_i(rd_done)
        ,.ex_cmd_o(ex_cmd), .ex_v_o(ex_v), .ex_ready_i(ex_ready), .ex_done_i(ex_done)
        ,.cs_cmd_o(cs_cmd), .cs_v_o(cs_v), .cs_ready_i(cs_ready), .cs_done_i(cs_done)
    );

    logic                  wr_mem_v;
    logic [BANK_ADDR_W_IFM_lp-1:0]  wr_mem_addr;
    logic [PSM_W_lp-1:0]   wr_mem_data;
    sp_bank_id_e           wr_mem_bank;

    write_ctrl #(.DIM_p(DIM_p)) u_wr (
         .clk_i, .reset_i
        ,.cmd_i      (wr_cmd)
        ,.v_i        (wr_v)
        ,.ready_o    (wr_ready)
        ,.done_o     (wr_done)
        ,.mem_v_o    (wr_mem_v)
        ,.mem_addr_o (wr_mem_addr)
        ,.mem_data_o (wr_mem_data)
        ,.mem_bank_o (wr_mem_bank)
    );

    logic                  ex_active;
    logic                  ex_ifm_r_v, ex_wgt_r_v, ex_psm_r_v;
    logic [BANK_ADDR_W_IFM_lp-1:0] ex_ifm_r_addr, ex_wgt_r_addr;
    logic [BANK_ADDR_W_PSM_lp-1:0] ex_psm_r_addr;
    logic [IFM_W_lp-1:0]   ex_ifm_r_data;
    logic [WGT_W_lp-1:0]   ex_wgt_r_data;
    logic [PSM_W_lp-1:0]   ex_psm_r_data;
    logic                  ex_psm_w_v;
    logic [BANK_ADDR_W_PSM_lp-1:0]  ex_psm_w_addr;
    logic [PSM_W_lp-1:0]   ex_psm_w_data;
    logic                  ex_ifm_w_v;  // TRANSPOSE op writeback
    logic [BANK_ADDR_W_IFM_lp-1:0]  ex_ifm_w_addr;
    logic [IFM_W_lp-1:0]   ex_ifm_w_data;

    logic signed [7:0]     tp_in_data   [DIM_p-1:0];
    logic                  tp_in_valid;
    logic                  tp_in_ready;  // back from transposer
    logic                  tp_transpose;
    logic                  tp_out_valid;
    logic                  tp_out_ready;  // forward to transposer
    logic signed [7:0]     tp_out_data  [DIM_p-1:0];

    mesh_req_t mreq;
    logic      mreq_v, mreq_ready, mreq_done;
    logic signed [7:0]  mesh_a_row    [DIM_p-1:0];
    logic signed [7:0]  mesh_w_row    [DIM_p-1:0];
    logic signed [31:0] mesh_b_row    [DIM_p-1:0];
    logic [CYC_W_lp-1:0] mesh_cycle;
    logic               mesh_cycle_v;
    logic signed [31:0] mesh_psum_row [DIM_p-1:0];
    logic               mesh_capture_v;
    logic [CYC_W_lp-1:0] mesh_capture_idx;

    logic signed [7:0]  m_in_weight  [DIM_p-1:0];
    logic               m_in_lock    [DIM_p-1:0];
    logic signed [7:0]  m_in_ifmap   [DIM_p-1:0];
    logic signed [31:0] m_in_psum    [DIM_p-1:0];
    logic               m_in_prop, m_in_valid, m_in_last;
    logic signed [31:0] m_out_psum   [DIM_p-1:0];
    logic               m_out_valid, m_out_last;

    logic ex_transpose_conflict;

    exec_ctrl #(.DIM_p(DIM_p)) u_ex (
         .clk_i, .reset_i
        ,.cmd_i        (ex_cmd)
        ,.v_i          (ex_v)
        ,.ready_o      (ex_ready)
        ,.done_o       (ex_done)
        ,.ex_active_o  (ex_active)
        ,.ifm_r_v_o    (ex_ifm_r_v),  .ifm_r_addr_o(ex_ifm_r_addr), .ifm_r_data_i(ex_ifm_r_data)
        ,.wgt_r_v_o    (ex_wgt_r_v),  .wgt_r_addr_o(ex_wgt_r_addr), .wgt_r_data_i(ex_wgt_r_data)
        ,.psm_r_v_o    (ex_psm_r_v),  .psm_r_addr_o(ex_psm_r_addr), .psm_r_data_i(ex_psm_r_data)
        ,.psm_w_v_o    (ex_psm_w_v),  .psm_w_addr_o(ex_psm_w_addr), .psm_w_data_o(ex_psm_w_data)
        ,.ifm_w_v_o    (ex_ifm_w_v),  .ifm_w_addr_o(ex_ifm_w_addr), .ifm_w_data_o(ex_ifm_w_data)
        ,.tp_in_data_o (tp_in_data)
        ,.tp_in_valid_o(tp_in_valid)
        ,.tp_transpose_o(tp_transpose)
        ,.tp_out_ready_o(tp_out_ready)
        ,.tp_in_ready_i (tp_in_ready)
        ,.tp_out_valid_i(tp_out_valid)
        ,.tp_out_data_i (tp_out_data)
        ,.mreq_o       (mreq)
        ,.mreq_v_o     (mreq_v)
        ,.mreq_ready_i (mreq_ready)
        ,.mreq_done_i  (mreq_done)
        ,.mesh_ifmap_row_o   (mesh_a_row)
        ,.mesh_weight_row_o  (mesh_w_row)
        ,.mesh_bias_row_o    (mesh_b_row)
        ,.mesh_cycle_i       (mesh_cycle)
        ,.mesh_cycle_v_i     (mesh_cycle_v)
        ,.mesh_psum_row_i    (mesh_psum_row)
        ,.mesh_capture_v_i   (mesh_capture_v)
        ,.mesh_capture_idx_i (mesh_capture_idx)
        ,.transpose_conflict_o (ex_transpose_conflict)
    );

    transpose #(
         .DIM_p   (DIM_p)
        ,.WIDTH_p (8)
    ) u_tp (
         .clk_i   (clk_i)
        ,.rst_n_i (rst_n_i)  // active-low reset
        ,.in_data (tp_in_data)
        ,.valid_i (tp_in_valid)
        ,.ready_i (tp_out_ready)  // downstream ready (mesh consuming)
        ,.transpose(tp_transpose)
        ,.valid_o (tp_out_valid)
        ,.ready_o (tp_in_ready)  // back to exec_ctrl
        ,.out_data(tp_out_data)
    );

    logic md_overflow;

    mesh_driver #(.DIM_p(DIM_p), .IFM_W_p(8), .WGT_W_p(8), .PSM_W_p(32)) u_md (
         .clk_i, .reset_i
        ,.req_i        (mreq)
        ,.req_v_i      (mreq_v)
        ,.req_ready_o  (mreq_ready)
        ,.done_o       (mreq_done)
        ,.ifmap_row_i  (mesh_a_row)
        ,.weight_row_i (mesh_w_row)
        ,.bias_row_i   (mesh_b_row)
        ,.cycle_o      (mesh_cycle)
        ,.cycle_v_o    (mesh_cycle_v)
        ,.psum_row_o   (mesh_psum_row)
        ,.capture_v_o  (mesh_capture_v)
        ,.capture_idx_o(mesh_capture_idx)
        ,.overflow_o   (md_overflow)
        ,.mesh_in_weight_o   (m_in_weight)
        ,.mesh_in_lock_o     (m_in_lock)
        ,.mesh_in_ifmap_o    (m_in_ifmap)
        ,.mesh_in_psum_o     (m_in_psum)
        ,.mesh_in_propagate_o(m_in_prop)
        ,.mesh_in_valid_o    (m_in_valid)
        ,.mesh_in_last_o     (m_in_last)
        ,.mesh_out_psum_i    (m_out_psum)
        ,.mesh_out_valid_i   (m_out_valid)
        ,.mesh_out_last_i    (m_out_last)
    );

    TwistMesh #(
         .N_p           (DIM_p)
        ,.INPUT_WIDTH_p (8)
        ,.WEIGHT_WIDTH_p(8)
        ,.OUTPUT_WIDTH_p(32)
    ) u_mesh (
         .clk_i, .reset_i
        ,.in_weight_i   (m_in_weight)
        ,.in_lock_i     (m_in_lock)
        ,.in_ifmap_i    (m_in_ifmap)
        ,.in_psum_i     (m_in_psum)
        ,.in_propagate_i(m_in_prop)
        ,.in_valid_i    (m_in_valid)
        ,.in_last_i     (m_in_last)
        ,.out_psum_o    (m_out_psum)
        ,.out_valid_o   (m_out_valid)
        ,.out_last_o    (m_out_last)
    );

    logic                  rd_active;
    logic                  rd_mem_v;
    logic [BANK_ADDR_W_IFM_lp-1:0]  rd_mem_addr;
    sp_bank_id_e           rd_mem_bank;
    logic [PSM_W_lp-1:0]   rd_mem_data;  // widest
    logic [255:0]          rd_pkt;
    logic                  rd_pkt_v, rd_pkt_ready;
    logic [3:0]            rd_pkt_size;
    logic [63:0]           csr_data_lo;  // current csr.data_o

    read_ctrl #(.DIM_p(DIM_p)) u_rd (
         .clk_i, .reset_i
        ,.cmd_i      (rd_cmd)
        ,.v_i        (rd_v)
        ,.ready_o    (rd_ready)
        ,.done_o     (rd_done)
        ,.rd_active_o(rd_active)
        ,.mem_v_o    (rd_mem_v)
        ,.mem_addr_o (rd_mem_addr)
        ,.mem_bank_o (rd_mem_bank)
        ,.mem_data_i (rd_mem_data)
        ,.csr_data_i (csr_data_lo)
        ,.pkt_o      (rd_pkt)
        ,.pkt_v_o    (rd_pkt_v)
        ,.pkt_size_o (rd_pkt_size)
        ,.pkt_ready_i(rd_pkt_ready)
    );

    logic mem_conflict;

    logic                  ifm_w_v, ifm_r_v, wgt_w_v, wgt_r_v, psm_w_v, psm_r_v;
    logic [BANK_ADDR_W_IFM_lp-1:0] ifm_w_addr, ifm_r_addr, wgt_w_addr, wgt_r_addr;
    logic [BANK_ADDR_W_PSM_lp-1:0] psm_w_addr, psm_r_addr;
    logic [IFM_W_lp-1:0]   ifm_w_data, ifm_r_data;
    logic [WGT_W_lp-1:0]   wgt_w_data, wgt_r_data;
    logic [PSM_W_lp-1:0]   psm_w_data, psm_r_data;
    logic                  rom_dropped;

    mem_arbiter #(.DIM_p(DIM_p)) u_marb (
         .clk_i, .reset_i
        ,.ex_active_i      (ex_active)
        ,.ex_ifm_r_v_i     (ex_ifm_r_v),    .ex_ifm_r_addr_i(ex_ifm_r_addr), .ex_ifm_r_data_o(ex_ifm_r_data)
        ,.ex_wgt_r_v_i     (ex_wgt_r_v),    .ex_wgt_r_addr_i(ex_wgt_r_addr), .ex_wgt_r_data_o(ex_wgt_r_data)
        ,.ex_psm_r_v_i     (ex_psm_r_v),    .ex_psm_r_addr_i(ex_psm_r_addr), .ex_psm_r_data_o(ex_psm_r_data)
        ,.ex_psm_w_v_i     (ex_psm_w_v),    .ex_psm_w_addr_i(ex_psm_w_addr), .ex_psm_w_data_i(ex_psm_w_data)
        ,.ex_ifm_w_v_i     (ex_ifm_w_v),    .ex_ifm_w_addr_i(ex_ifm_w_addr), .ex_ifm_w_data_i(ex_ifm_w_data)
        ,.wr_v_i           (wr_mem_v)
        ,.wr_addr_i        (wr_mem_addr)
        ,.wr_data_i        (wr_mem_data)
        ,.wr_bank_i        (wr_mem_bank)
        ,.rd_v_i           (rd_mem_v)
        ,.rd_addr_i        (rd_mem_addr)
        ,.rd_bank_i        (rd_mem_bank)
        ,.rd_data_o        (rd_mem_data)
        ,.ifm_w_v_o    (ifm_w_v), .ifm_w_addr_o(ifm_w_addr), .ifm_w_data_o(ifm_w_data)
        ,.ifm_r_v_o    (ifm_r_v), .ifm_r_addr_o(ifm_r_addr), .ifm_r_data_i(ifm_r_data)
        ,.wgt_w_v_o    (wgt_w_v), .wgt_w_addr_o(wgt_w_addr), .wgt_w_data_o(wgt_w_data)
        ,.wgt_r_v_o    (wgt_r_v), .wgt_r_addr_o(wgt_r_addr), .wgt_r_data_i(wgt_r_data)
        ,.psm_w_v_o    (psm_w_v), .psm_w_addr_o(psm_w_addr), .psm_w_data_o(psm_w_data)
        ,.psm_r_v_o    (psm_r_v), .psm_r_addr_o(psm_r_addr), .psm_r_data_i(psm_r_data)
        ,.mem_conflict_o(mem_conflict)
    );

    scratchpad #(.DIM_p(DIM_p)) u_sp (
         .clk_i, .reset_i
        ,.ifm_w_v_i(ifm_w_v), .ifm_w_addr_i(ifm_w_addr), .ifm_w_data_i(ifm_w_data)
        ,.ifm_r_v_i(ifm_r_v), .ifm_r_addr_i(ifm_r_addr), .ifm_r_data_o(ifm_r_data)
        ,.wgt_w_v_i(wgt_w_v), .wgt_w_addr_i(wgt_w_addr), .wgt_w_data_i(wgt_w_data)
        ,.wgt_r_v_i(wgt_r_v), .wgt_r_addr_i(wgt_r_addr), .wgt_r_data_o(wgt_r_data)
        ,.psm_w_v_i(psm_w_v), .psm_w_addr_i(psm_w_addr), .psm_w_data_i(psm_w_data)
        ,.psm_r_v_i(psm_r_v), .psm_r_addr_i(psm_r_addr), .psm_r_data_o(psm_r_data)
        ,.write_to_rom_o(rom_dropped)
    );

    logic [63:0] csr_data_to;
    logic [1:0]  csr_mode;
    logic [63:0] _csr_read_data_o_unused;  // redundant — read_ctrl uses csr_data_lo
    logic        _csr_read_v_o_unused;

    csr_router u_csr_r (
         .clk_i, .reset_i
        ,.cmd_i           (cs_cmd)
        ,.v_i             (cs_v)
        ,.ready_o         (cs_ready)
        ,.done_o          (cs_done)
        ,.err_decoder_i             (dec_err)
        ,.err_mem_conflict_i        (mem_conflict)
        ,.err_write_rom_i           (rom_dropped)
        ,.err_overflow_i            (md_overflow)
        ,.err_transpose_conflict_i  (ex_transpose_conflict)
        ,.csr_data_o      (csr_data_to)
        ,.csr_mode_o      (csr_mode)
        ,.csr_data_i      (csr_data_lo)
        ,.read_csr_data_o (_csr_read_data_o_unused)
        ,.read_csr_v_o    (_csr_read_v_o_unused)
    );

    csr #(.WIDTH_p(64)) u_csr_reg (
         .clk_i        (clk_i)
        ,.rst_n_i      (rst_n_i)
        ,.data_i       (csr_data_to)
        ,.write_mode_i (csr_mode)
        ,.data_o       (csr_data_lo)
    );

    logic [31:0] out_flit;
    logic        out_flit_v, out_flit_ready;

    depacketizer #(
         .packet_width_p (256)
        ,.flit_width_p   (32)
        ,.fifo_els_p     (4)
    ) u_depack (
         .clk_i           (clk_i)
        ,.reset_i         (reset_i)
        ,.packet_i        (rd_pkt)
        ,.valid_i         (rd_pkt_v)
        ,.packet_size_i   (rd_pkt_size)
        ,.ready_o         (rd_pkt_ready)
        ,.flit_o          (out_flit)
        ,.valid_o         (out_flit_v)
        ,.ready_i         (out_flit_ready)
    );

    assign link_out_v_o = out_flit_v;
    assign link_out_data_o = out_flit;
    assign out_flit_ready = link_out_yumi_i;

endmodule
