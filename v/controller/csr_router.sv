
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

    ,output logic [63:0]  packet_o
    ,output logic         packet_v_o
    ,output logic [2:0]   packet_size_o
    ,input  logic         packet_r_i
);

    typedef enum logic [1:0] {
        S_IDLE,
        S_SEND_HDR,
        S_SEND_DATA,
        S_DONE
    } st_e;

    st_e st_r, st_n;

    logic is_write;
    assign is_write = (cmd_i.op == OP_WRITE_CSR) || (cmd_i.op == OP_ERROR_CSR);

    always_comb begin 
        st_n = st_r;
        case(st_r)
            S_IDLE:         st_n = v_i ? S_SEND_HDR : S_IDLE;
            S_SEND_HDR:     st_n = packet_r_i ? (is_write ? S_DONE : S_SEND_DATA) : S_SEND_HDR;
            S_SEND_DATA:    st_n = packet_r_i ? S_DONE : S_SEND_DATA;
            S_DONE:         st_n = S_IDLE;
            default:        st_n = S_IDLE;
        endcase
    end

    logic [31:0] header_packet;

    always_comb begin 
        packet_o = '0;
        packet_size_o = '0;
        header_packet = '0;
        case(st_r)
            S_SEND_HDR: begin 
                header_packet[5:0] = cmd_i.op;
                packet_o = {header_packet, 32'b0};
                packet_size_o = 1;
            end
            S_SEND_DATA: begin 
                packet_o = csr_data_i;
                packet_size_o = 2;
            end
            default: ;
        endcase
    end

    assign packet_v_o = (st_r == S_SEND_HDR) || (st_r == S_SEND_DATA);
    


    assign ready_o = (st_r == S_IDLE);
    assign done_o  = (st_r == S_DONE);

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
        if (reset_i) begin 
            accept_r <= 1'b0;
            st_r <= S_IDLE;
        end
        else begin 
            accept_r <= v_i;
            st_r <= st_n;
        end
    end

endmodule
