
import scratchpad_pkg::*;
import ctrl_pkg::*;

module mem_arbiter #(
     parameter int DIM_p                = scratchpad_pkg::DIM_p
    ,localparam int IFM_W_lp            = scratchpad_pkg::IFM_ROW_W_lp
    ,localparam int WGT_W_lp            = scratchpad_pkg::WGT_ROW_W_lp
    ,localparam int PSM_W_lp            = scratchpad_pkg::PSM_ROW_W_lp
    ,localparam int BANK_DEPTH_IFM_lp   = scratchpad_pkg::BANK_DEPTH_IFM_lp
    ,localparam int BANK_DEPTH_PSM_lp   = scratchpad_pkg::BANK_DEPTH_PSM_lp    
    ,localparam int IFM_ADDR_W_lp       = scratchpad_pkg::BANK_ADDR_W_IFM_lp
    ,localparam int PSM_ADDR_W_lp       = scratchpad_pkg::BANK_ADDR_W_PSM_lp
)(
     input  logic                    clk_i
    ,input  logic                    reset_i

    ,input  logic                       ex_active_i  // owns scratchpad
    ,input  logic                       ex_ifm_r_v_i
    ,input  logic [IFM_ADDR_W_lp-1:0]   ex_ifm_r_addr_i
    ,output logic [IFM_W_lp-1:0]        ex_ifm_r_data_o
    ,input  logic                       ex_wgt_r_v_i
    ,input  logic [IFM_ADDR_W_lp-1:0]   ex_wgt_r_addr_i
    ,output logic [WGT_W_lp-1:0]        ex_wgt_r_data_o
    ,input  logic                       ex_psm_r_v_i
    ,input  logic [PSM_ADDR_W_lp-1:0]   ex_psm_r_addr_i
    ,output logic [PSM_W_lp-1:0]        ex_psm_r_data_o
    ,input  logic                       ex_psm_w_v_i
    ,input  logic [PSM_ADDR_W_lp-1:0]    ex_psm_w_addr_i
    ,input  logic [PSM_W_lp-1:0]        ex_psm_w_data_i

    ,input  logic                       ex_ifm_w_v_i
    ,input  logic [IFM_ADDR_W_lp-1:0]   ex_ifm_w_addr_i
    ,input  logic [IFM_W_lp-1:0]        ex_ifm_w_data_i

    ,input  logic                       wr_v_i
    ,input  logic [IFM_ADDR_W_lp-1:0]   wr_addr_i  // widest possible address
    ,input  logic [PSM_W_lp-1:0]        wr_data_i  // widest possible payload
    ,input  sp_bank_id_e                wr_bank_i

    ,input  logic                       rd_v_i
    ,input  logic [IFM_ADDR_W_lp-1:0]   rd_addr_i
    ,input  sp_bank_id_e                rd_bank_i
    ,output logic [PSM_W_lp-1:0]        rd_data_o  // sized to widest

    ,output logic                       ifm_w_v_o
    ,output logic [IFM_ADDR_W_lp-1:0]   ifm_w_addr_o
    ,output logic [IFM_W_lp-1:0]        ifm_w_data_o
    ,output logic                       ifm_r_v_o
    ,output logic [IFM_ADDR_W_lp-1:0]   ifm_r_addr_o
    ,input  logic [IFM_W_lp-1:0]        ifm_r_data_i

    ,output logic                       wgt_w_v_o
    ,output logic [IFM_ADDR_W_lp-1:0]   wgt_w_addr_o
    ,output logic [WGT_W_lp-1:0]        wgt_w_data_o
    ,output logic                       wgt_r_v_o
    ,output logic [IFM_ADDR_W_lp-1:0]   wgt_r_addr_o
    ,input  logic [WGT_W_lp-1:0]        wgt_r_data_i

    ,output logic                       psm_w_v_o
    ,output logic [PSM_ADDR_W_lp-1:0]   psm_w_addr_o
    ,output logic [PSM_W_lp-1:0]        psm_w_data_o
    ,output logic                       psm_r_v_o
    ,output logic [PSM_ADDR_W_lp-1:0]   psm_r_addr_o
    ,input  logic [PSM_W_lp-1:0]        psm_r_data_i

    ,output logic                       mem_conflict_o
);


    logic wr_v_ifm, wr_v_wgt, wr_v_psm;
    assign wr_v_ifm = wr_v_i & (wr_bank_i == BANK_IFMAP);
    assign wr_v_wgt = wr_v_i & ((wr_bank_i == BANK_WEIGHT)
                                | (wr_bank_i == BANK_IFMAP));  // mirror writes
    assign wr_v_psm = wr_v_i & (wr_bank_i == BANK_PSUM);

    logic rd_v_ifm, rd_v_wgt, rd_v_psm;
    assign rd_v_ifm = rd_v_i & (rd_bank_i == BANK_IFMAP);
    assign rd_v_wgt = rd_v_i & (rd_bank_i == BANK_WEIGHT);
    assign rd_v_psm = rd_v_i & (rd_bank_i == BANK_PSUM);

    assign mem_conflict_o = ex_active_i & (wr_v_i | rd_v_i);

    assign ifm_w_v_o    = ex_active_i ? ex_ifm_w_v_i   : wr_v_ifm;
    assign ifm_w_addr_o = ex_active_i ? ex_ifm_w_addr_i: wr_addr_i;
    assign ifm_w_data_o = ex_active_i ? ex_ifm_w_data_i: wr_data_i[IFM_W_lp-1:0];
    assign ifm_r_v_o    = ex_active_i ? ex_ifm_r_v_i   : rd_v_ifm;
    assign ifm_r_addr_o = ex_active_i ? ex_ifm_r_addr_i: rd_addr_i;
    assign ex_ifm_r_data_o = ifm_r_data_i;

    assign wgt_w_v_o    = ex_active_i ? ex_ifm_w_v_i    : wr_v_wgt;
    assign wgt_w_addr_o = ex_active_i ? ex_ifm_w_addr_i : wr_addr_i;
    assign wgt_w_data_o = ex_active_i ? ex_ifm_w_data_i : wr_data_i[WGT_W_lp-1:0];
    assign wgt_r_v_o    = ex_active_i ? ex_wgt_r_v_i   : rd_v_wgt;
    assign wgt_r_addr_o = ex_active_i ? ex_wgt_r_addr_i: rd_addr_i;
    assign ex_wgt_r_data_o = wgt_r_data_i;

    // TODO: verify address bit widths match
    assign psm_w_v_o    = ex_active_i ? ex_psm_w_v_i   : wr_v_psm;
    assign psm_w_addr_o = ex_active_i ? ex_psm_w_addr_i: wr_addr_i[PSM_ADDR_W_lp-1:0];
    assign psm_w_data_o = ex_active_i ? ex_psm_w_data_i: wr_data_i;
    assign psm_r_v_o    = ex_active_i ? ex_psm_r_v_i   : rd_v_psm;
    assign psm_r_addr_o = ex_active_i ? ex_psm_r_addr_i: rd_addr_i[PSM_ADDR_W_lp-1:0];
    assign ex_psm_r_data_o = psm_r_data_i;

    always_comb begin
        rd_data_o = '0;
        unique case (rd_bank_i)
            BANK_IFMAP:  rd_data_o[IFM_W_lp-1:0] = ifm_r_data_i;
            BANK_WEIGHT: rd_data_o[WGT_W_lp-1:0] = wgt_r_data_i;
            BANK_PSUM:   rd_data_o              = psm_r_data_i;
            default:     rd_data_o              = '0;
        endcase
    end

endmodule
