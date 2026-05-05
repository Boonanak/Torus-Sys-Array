
module sp_bank #(
     parameter int WIDTH_p          = 32  // row width in bits
    ,parameter int DEPTH_p          = 256  // entries
    ,parameter int ROM_IDENTITY_p   = 0
    ,parameter int ROM_ZERO_p       = 0
    ,parameter int DIM_p            = 4  // for identity row generation
    ,parameter int ELEM_WIDTH_p     = 8  // per-element width
    ,localparam int ADDR_W_lp       = $clog2(DEPTH_p)
)(
     input  logic                    clk_i
    ,input  logic                    reset_i

    ,input  logic                    w_v_i
    ,input  logic [ADDR_W_lp-1:0]    w_addr_i
    ,input  logic [WIDTH_p-1:0]      w_data_i
    ,output logic                    w_dropped_o  // pulses when write hit ROM

    ,input  logic                    r_v_i
    ,input  logic [ADDR_W_lp-1:0]    r_addr_i
    ,output logic [WIDTH_p-1:0]      r_data_o
);

    localparam logic [ADDR_W_lp-1:0] IDENTITY_LO_lp = (62 * DIM_p);
    localparam logic [ADDR_W_lp-1:0] IDENTITY_HI_lp = (62 * DIM_p) + DIM_p - 1;  // inclusive
    localparam logic [ADDR_W_lp-1:0] ZERO_LO_lp     = (62 * DIM_p);  // zero spans 62-63 (int19)
    localparam logic [ADDR_W_lp-1:0] ZERO_HI_lp     = (62 * DIM_p) + 2*DIM_p - 1;  // inclusive

    logic addr_in_identity_w, addr_in_identity_r;
    logic addr_in_zero_w,     addr_in_zero_r;

    assign addr_in_identity_w = (ROM_IDENTITY_p != 0) &&
        (w_addr_i >= IDENTITY_LO_lp) &&
        (w_addr_i <= IDENTITY_HI_lp);
    assign addr_in_identity_r = (ROM_IDENTITY_p != 0) &&
        (r_addr_i >= IDENTITY_LO_lp) &&
        (r_addr_i <= IDENTITY_HI_lp);
    assign addr_in_zero_w     = (ROM_ZERO_p != 0) &&
        (w_addr_i >= ZERO_LO_lp) &&
        (w_addr_i <= ZERO_HI_lp);
    assign addr_in_zero_r     = (ROM_ZERO_p != 0) &&
        (r_addr_i >= ZERO_LO_lp) &&
        (r_addr_i <= ZERO_HI_lp);

    assign w_dropped_o = w_v_i && (addr_in_identity_w || addr_in_zero_w);

    logic                    mem_w_v;
    assign mem_w_v = w_v_i && !addr_in_identity_w && !addr_in_zero_w;

    function automatic logic [WIDTH_p-1:0]
            identity_row(input logic [ADDR_W_lp-1:0] addr);
        logic [WIDTH_p-1:0] v;
        int row_idx;
        v = '0;
        row_idx = addr - IDENTITY_LO_lp;
        v[row_idx*ELEM_WIDTH_p +: ELEM_WIDTH_p] = 1;
        return v;
    endfunction

    logic [WIDTH_p-1:0] mem_r_data;

    bsg_mem_1r1w #(
         .width_p             (WIDTH_p)
        ,.els_p               (DEPTH_p)
        ,.read_write_same_addr_p(0)
    ) u_bank (
         .w_clk_i   (clk_i)
        ,.w_reset_i (reset_i)
        ,.w_v_i     (mem_w_v)
        ,.w_addr_i  (w_addr_i)
        ,.w_data_i  (w_data_i)
        ,.r_v_i     (r_v_i)
        ,.r_addr_i  (r_addr_i)
        ,.r_data_o  (mem_r_data)
    );

    always_comb begin
        if (addr_in_zero_r)            r_data_o = '0;
        else if (addr_in_identity_r)   r_data_o = identity_row(r_addr_i);
        else                           r_data_o = mem_r_data;
    end

endmodule
