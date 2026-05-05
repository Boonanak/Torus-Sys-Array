
import ctrl_pkg::*;

module csr_router (
     input  logic         clk_i
    ,input  logic         reset_i

    ,input  decoded_cmd_t cmd_i
    ,input  logic         v_i
    ,output logic         ready_o
    ,output logic         done_o

    ,input  err_pulse_t   err_decoder_i
    ,input  logic         err_mem_conflict_i
    ,input  logic         err_write_rom_i
    ,input  logic         err_overflow_i
    ,input  logic         err_transpose_conflict_i

    ,output logic [63:0]  csr_data_o
    ,output logic [1:0]   csr_mode_o
    ,input  logic [63:0]  csr_data_i  // current value (for READ_CSR)

    ,output logic [63:0]  read_csr_data_o
    ,output logic         read_csr_v_o
);

    assign ready_o = 1'b1;

    logic [63:0] err_set_word;
    always_comb begin
        err_set_word = '0;
        if (err_overflow_i)              err_set_word[CSR_BIT_OVERFLOW]           = 1'b1;
        if (err_write_rom_i)             err_set_word[CSR_BIT_WRITE_ROM]          = 1'b1;
        if (err_decoder_i.invalid_op)    err_set_word[CSR_BIT_INVALID_OP]         = 1'b1;
        if (err_mem_conflict_i)          err_set_word[CSR_BIT_MEM_CONFLICT]       = 1'b1;
        if (err_transpose_conflict_i)    err_set_word[CSR_BIT_TRANSPOSE_CONFLICT] = 1'b1;
        if (|err_set_word[CSR_BIT_TRANSPOSE_CONFLICT:CSR_BIT_OVERFLOW])
                                         err_set_word[CSR_BIT_ERROR_ANY]          = 1'b1;
    end

    logic do_clear_parity;
    assign do_clear_parity = err_decoder_i.parity_fail;
    logic [63:0] parity_clear_mask;
    assign parity_clear_mask = (do_clear_parity ? (64'd1 << CSR_BIT_PARITY_OK) : '0);

    logic do_write_csr, do_error_csr, do_set_err;
    assign do_write_csr = v_i & (cmd_i.op == OP_WRITE_CSR);
    assign do_error_csr = v_i & (cmd_i.op == OP_ERROR_CSR);
    assign do_set_err   = (err_set_word != '0);

    always_comb begin
        csr_mode_o = 2'b00;
        csr_data_o = '0;
        if (do_write_csr) begin
            csr_mode_o = 2'b11;  // assign
            csr_data_o = cmd_i.imm_data;
        end else if (do_error_csr) begin
            csr_mode_o = 2'b10;  // clear
            csr_data_o = CSR_ERR_MASK;
        end else if (do_clear_parity) begin
            csr_mode_o = 2'b10;  // clear PARITY_OK
            csr_data_o = parity_clear_mask;
        end else if (do_set_err) begin
            csr_mode_o = 2'b01;  // set
            csr_data_o = err_set_word;
        end
    end

    assign read_csr_data_o = csr_data_i;
    assign read_csr_v_o    = v_i & (cmd_i.op == OP_READ_CSR);

    logic accept_r;
    always_ff @(posedge clk_i) begin
        if (reset_i) accept_r <= 1'b0;
        else         accept_r <= v_i;
    end
    assign done_o = accept_r;

endmodule
