
import scratchpad_pkg::*;

module scratchpad #(
     parameter int DIM_p           = scratchpad_pkg::DIM_p
    ,parameter int NUM_MATRICES_p  = scratchpad_pkg::NUM_MATRICES_p
    ,localparam int IFM_W_lp       = DIM_p * 8
    ,localparam int WGT_W_lp       = DIM_p * 8
    ,localparam int PSM_W_lp       = DIM_p * 16  // 16b/element in bank; sign-ext to 19b for mesh, truncate 19→16 on writeback
    ,localparam int DEPTH_lp       = NUM_MATRICES_p * DIM_p
    ,localparam int ADDR_W_lp      = $clog2(DEPTH_lp)
)(
     input  logic                    clk_i
    ,input  logic                    reset_i

    ,input  logic                    ifm_w_v_i
    ,input  logic [ADDR_W_lp-1:0]    ifm_w_addr_i
    ,input  logic [IFM_W_lp-1:0]     ifm_w_data_i
    ,input  logic                    ifm_r_v_i
    ,input  logic [ADDR_W_lp-1:0]    ifm_r_addr_i
    ,output logic [IFM_W_lp-1:0]     ifm_r_data_o

    ,input  logic                    wgt_w_v_i
    ,input  logic [ADDR_W_lp-1:0]    wgt_w_addr_i
    ,input  logic [WGT_W_lp-1:0]     wgt_w_data_i
    ,input  logic                    wgt_r_v_i
    ,input  logic [ADDR_W_lp-1:0]    wgt_r_addr_i
    ,output logic [WGT_W_lp-1:0]     wgt_r_data_o

    ,input  logic                    psm_w_v_i
    ,input  logic [ADDR_W_lp-1:0]    psm_w_addr_i
    ,input  logic [PSM_W_lp-1:0]     psm_w_data_i
    ,input  logic                    psm_r_v_i
    ,input  logic [ADDR_W_lp-1:0]    psm_r_addr_i
    ,output logic [PSM_W_lp-1:0]     psm_r_data_o

    ,output logic                    write_to_rom_o  // pulse on any bank
);

    logic ifm_dropped, wgt_dropped, psm_dropped;
    assign write_to_rom_o = ifm_dropped | wgt_dropped | psm_dropped;

    sp_bank #(
         .WIDTH_p        (IFM_W_lp)
        ,.DEPTH_p        (DEPTH_lp)
        ,.ROM_IDENTITY_p (1)  // identity needed when BaseAddr 62 is A source
        ,.ROM_ZERO_p     (0)
        ,.DIM_p          (DIM_p)
        ,.ELEM_WIDTH_p   (8)
    ) u_ifmap (
         .clk_i, .reset_i
        ,.w_v_i      (ifm_w_v_i)
        ,.w_addr_i   (ifm_w_addr_i)
        ,.w_data_i   (ifm_w_data_i)
        ,.w_dropped_o(ifm_dropped)
        ,.r_v_i      (ifm_r_v_i)
        ,.r_addr_i   (ifm_r_addr_i)
        ,.r_data_o   (ifm_r_data_o)
    );

    sp_bank #(
         .WIDTH_p        (WGT_W_lp)
        ,.DEPTH_p        (DEPTH_lp)
        ,.ROM_IDENTITY_p (1)
        ,.ROM_ZERO_p     (0)
        ,.DIM_p          (DIM_p)
        ,.ELEM_WIDTH_p   (8)
    ) u_weight (
         .clk_i, .reset_i
        ,.w_v_i      (wgt_w_v_i)
        ,.w_addr_i   (wgt_w_addr_i)
        ,.w_data_i   (wgt_w_data_i)
        ,.w_dropped_o(wgt_dropped)
        ,.r_v_i      (wgt_r_v_i)
        ,.r_addr_i   (wgt_r_addr_i)
        ,.r_data_o   (wgt_r_data_o)
    );

    sp_bank #(
         .WIDTH_p        (PSM_W_lp)
        ,.DEPTH_p        (DEPTH_lp)
        ,.ROM_IDENTITY_p (0)
        ,.ROM_ZERO_p     (1)
        ,.DIM_p          (DIM_p)
        ,.ELEM_WIDTH_p   (16)  // psum element width in bank (mesh-internal is 19b)
    ) u_psum (
         .clk_i, .reset_i
        ,.w_v_i      (psm_w_v_i)
        ,.w_addr_i   (psm_w_addr_i)
        ,.w_data_i   (psm_w_data_i)
        ,.w_dropped_o(psm_dropped)
        ,.r_v_i      (psm_r_v_i)
        ,.r_addr_i   (psm_r_addr_i)
        ,.r_data_o   (psm_r_data_o)
    );

endmodule
