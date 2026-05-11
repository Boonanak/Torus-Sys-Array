import ctrl_pkg::*;

module cmd_decoder (
     input  logic                       clk_i
    ,input  logic                       reset_i

    ,input  logic [FLIT_W_p-1:0]        flit_i
    ,input  logic                       flit_v_i
    ,input  logic                       flit_parity_ok_i
    ,output logic                       flit_ready_o

    ,output decoded_cmd_t               cmd_o
    ,output logic                       cmd_v_o
    ,input  logic                       cmd_ready_i

    ,output err_pulse_t                 err_o
);

    localparam int vaddr_width_p = ctrl_pkg::vaddr_width_p;
    localparam int baddr_width_p = ctrl_pkg::baddr_width_p;
    
    // Four-state FSM definition
    typedef enum logic [1:0] { S_HEAD, S_DATA0, S_DATA1, S_SEND } state_e;
    state_e st_r, st_n;

    decoded_cmd_t cmd_r, cmd_n;
    err_pulse_t   err_n;

    // Header decoding wires
    opcode_e                  hdr_op;
    logic [baddr_width_p-1:0] hdr_dest, hdr_src, hdr_acc, hdr_weight;
    logic [vaddr_width_p-1:0] hdr_vaddr;
    logic                     is_writeish, is_readv, hdr_known;

    assign hdr_op     = opcode_e'(flit_i[5:0]);
    assign hdr_dest   = flit_i[31 -: baddr_width_p];
    assign hdr_src    = flit_i[25 -: baddr_width_p];
    assign hdr_acc    = flit_i[19 -: baddr_width_p];
    assign hdr_weight = flit_i[13 -: baddr_width_p];

    assign is_writeish = (hdr_op == OP_WRITE_8) || (hdr_op == OP_WRITE_32) || (hdr_op == OP_WRITE_CSR);
    assign is_readv    = (hdr_op == OP_READV8) || (hdr_op == OP_READV16);
    assign hdr_vaddr   = is_writeish ? flit_i[31 -: vaddr_width_p] :
                         is_readv    ? flit_i[25 -: vaddr_width_p] : '0;

    always_comb begin
        case (hdr_op)
            OP_NOOP, OP_READV8, OP_READM8, OP_READV16, OP_READM16,
            OP_READ_CSR, OP_WRITE_8, OP_WRITE_32, OP_WRITE_CSR, OP_TRANSPOSE,
            OP_ERROR_CSR, OP_CC, OP_CR, OP_LC, OP_LCCC, OP_LCCR,
            OP_LR, OP_LRCC, OP_LRCR:  hdr_known = 1'b1;
            default:                  hdr_known = 1'b0;
        endcase
    end

    // Handshake logic
    assign flit_ready_o = (st_r != S_SEND);
    assign cmd_v_o      = (st_r == S_SEND);
    assign cmd_o        = cmd_r;
    assign err_o        = err_n;

    always_comb begin
        st_n  = st_r;
        cmd_n = cmd_r;
        err_n = '0;

        case (st_r)
            S_HEAD: begin
                if (flit_v_i) begin
                    if (!flit_parity_ok_i) begin
                        err_n.parity_fail = 1'b1;
                    end else if (!hdr_known) begin
                        err_n.invalid_op  = 1'b1;
                    end else begin
                        cmd_n.op           = hdr_op;
                        cmd_n.baddr_dest   = hdr_dest;
                        cmd_n.baddr_src    = hdr_src;
                        cmd_n.baddr_acc    = hdr_acc;
                        cmd_n.baddr_weight = hdr_weight;
                        cmd_n.vaddr        = hdr_vaddr;
                        cmd_n.imm_data     = '0;
                        
                        st_n = is_writeish ? S_DATA0 : S_SEND;
                    end
                end
            end

            S_DATA0: begin
                if (flit_v_i) begin
                    if (!flit_parity_ok_i) begin
                        err_n.parity_fail = 1'b1;
                        st_n              = S_HEAD;
                    end else begin
                        cmd_n.imm_data[63:32] = flit_i;
                        st_n                  = S_DATA1;
                    end
                end
            end

            S_DATA1: begin
                if (flit_v_i) begin
                    if (!flit_parity_ok_i) begin
                        err_n.parity_fail = 1'b1;
                        st_n              = S_HEAD;
                    end else begin
                        cmd_n.imm_data[31:0] = flit_i;
                        st_n                 = S_SEND;
                    end
                end
            end

            S_SEND: begin
                if (cmd_ready_i) begin
                    st_n = S_HEAD;
                end
            end

            default: st_n = S_HEAD;
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            st_r  <= S_HEAD;
            cmd_r <= '0;
        end else begin
            st_r  <= st_n;
            cmd_r <= cmd_n;
        end
    end

endmodule