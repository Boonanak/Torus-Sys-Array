
package scratchpad_pkg;

    parameter int DIM_p           = 8;
    parameter int NUM_MATRICES_IFM_p = 8;
    parameter int NUM_MATRICES_PSM_p = 4;
    parameter int IFM_WIDTH_p     = 8;
    parameter int WGT_WIDTH_p     = 8;
    parameter int PSM_WIDTH_p     = 32;  // bank stores 16b; mesh-internal psum is 19b (sign-ext on read into mesh, truncate on write back)

    parameter int IFM_ROW_W_lp    = DIM_p * IFM_WIDTH_p;
    parameter int WGT_ROW_W_lp    = DIM_p * WGT_WIDTH_p;
    parameter int PSM_ROW_W_lp    = DIM_p * PSM_WIDTH_p;

    parameter int BANK_DEPTH_IFM_lp   = NUM_MATRICES_IFM_p * DIM_p;
    parameter int BANK_DEPTH_PSM_lp   = NUM_MATRICES_PSM_p * DIM_p;
    parameter int BANK_ADDR_W_IFM_lp  = $clog2(BANK_DEPTH_IFM_lp);
    parameter int BANK_ADDR_W_PSM_lp  = $clog2(BANK_DEPTH_PSM_lp);

    typedef enum logic [1:0] {
        BANK_IFMAP   = 2'd0,
        BANK_WEIGHT  = 2'd1,
        BANK_PSUM    = 2'd2
    } sp_bank_id_e;

    // is this logic used?
    function automatic logic [BANK_ADDR_W_IFM_lp-1:0]
            base_to_row0(input logic [5:0] base);
        return base * DIM_p;  // synthesizable when DIM_p is pow2
    endfunction

endpackage
