
import ctrl_pkg::*;
import scratchpad_pkg::*;

module write_ctrl #(
     parameter int DIM_p = scratchpad_pkg::DIM_p
    ,parameter int NUM_MATRICES_p = scratchpad_pkg::NUM_MATRICES_p
    ,localparam int ADDR_W_lp = $clog2(NUM_MATRICES_p*DIM_p)
    ,localparam int PSM_W_lp = scratchpad_pkg::PSM_ROW_W_lp
)(
     input  logic          clk_i
    ,input  logic          reset_i

    ,input  decoded_cmd_t  cmd_i
    ,input  logic          v_i
    ,output logic          ready_o
    ,output logic          done_o

    ,output logic                    mem_v_o
    ,output logic [ADDR_W_lp-1:0]    mem_addr_o
    ,output logic [PSM_W_lp-1:0]     mem_data_o
    ,output sp_bank_id_e             mem_bank_o
);

    assign ready_o = 1'b1;  // always accept

    sp_bank_id_e sel_bank;
    always_comb begin
        if (cmd_i.vaddr[8])  sel_bank = BANK_PSUM;  // int19 region
        else                  sel_bank = BANK_IFMAP;  // int8 region (mirror to weight in arbiter)
    end

    assign mem_v_o    = v_i;
    assign mem_addr_o = cmd_i.vaddr[ADDR_W_lp-1:0];
    assign mem_data_o = {{(PSM_W_lp-64){1'b0}}, cmd_i.imm_data};
    assign mem_bank_o = sel_bank;

    logic accept_r;
    always_ff @(posedge clk_i) begin
        if (reset_i) accept_r <= 1'b0;
        else         accept_r <= v_i;
    end
    assign done_o = accept_r;

endmodule
