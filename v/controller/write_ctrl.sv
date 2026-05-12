
import ctrl_pkg::*;
import scratchpad_pkg::*;

module write_ctrl #(
     parameter int DIM_p            = scratchpad_pkg::DIM_p
    ,localparam int ADDR_W_lp       = scratchpad_pkg::BANK_ADDR_W_IFM_lp // widest of each
    ,localparam int IFM_W_lp        = scratchpad_pkg::IFM_ROW_W_lp
    ,localparam int PSM_W_lp        = scratchpad_pkg::PSM_ROW_W_lp
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

    ,output logic [31:0]   header_packet
    ,output logic          header_packet_valid
    ,input  logic          header_packet_ready
);

    assign ready_o = header_packet_ready;  // dont accept if we haven't finished previous write

    sp_bank_id_e sel_bank;
    always_comb begin
        if      (cmd_i.op == OP_WRITE_32)   sel_bank = BANK_PSUM;
        else if (cmd_i.op == OP_WRITE_8)    sel_bank = BANK_IFMAP;
        else                                sel_bank = BANK_IFMAP;  // default
    end

    assign mem_v_o    = v_i;
    assign mem_addr_o = cmd_i.vaddr[ADDR_W_lp-1:0];
    assign mem_data_o = (sel_bank == BANK_IFMAP) ? {{(PSM_W_lp-64){1'b0}}, cmd_i.imm_data[IFM_W_lp-1:0]}
                                                 : cmd_i.imm_data;
    assign mem_bank_o = sel_bank;

    always_comb begin
        header_packet = '0;
        header_packet[5:0] = cmd_i.op;
        header_packet[31 -: 9] = cmd_i.vaddr << 3;
        header_packet_valid = mem_v_o;
    end

    logic accept_r;
    always_ff @(posedge clk_i) begin
        if (reset_i) accept_r <= 1'b0;
        else         accept_r <= v_i && header_packet_ready;
    end
    assign done_o = accept_r;

endmodule
