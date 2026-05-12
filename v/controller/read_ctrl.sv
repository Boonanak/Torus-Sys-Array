import ctrl_pkg::*;
import scratchpad_pkg::*;

module read_ctrl #(
     parameter int DIM_p            = scratchpad_pkg::DIM_p
    ,parameter int PKT_W_p          = scratchpad_pkg::PSM_ROW_W_lp      // 256b
    ,parameter int FLIT_W_p         = 32                                // 32b flits
    ,localparam int ADDR_W_lp       = scratchpad_pkg::BANK_ADDR_W_IFM_lp
    ,localparam int IFM_W_lp        = scratchpad_pkg::IFM_ROW_W_lp
    ,localparam int PSM_W_lp        = scratchpad_pkg::PSM_ROW_W_lp
    ,localparam int CYC_W_lp  = $clog2(DIM_p+1)
    ,localparam int PKT_SIZE_W_lp = $clog2(PKT_W_p / FLIT_W_p) + 1
)(
     input  logic                       clk_i
    ,input  logic                       reset_i

    ,input  decoded_cmd_t               cmd_i
    ,input  logic                       v_i
    ,output logic                       ready_o
    ,output logic                       done_o

    ,output logic                       rd_active_o

    ,output logic                       mem_v_o
    ,output logic [ADDR_W_lp-1:0]       mem_addr_o
    ,output sp_bank_id_e                mem_bank_o
    ,input  logic [PSM_W_lp-1:0]        mem_data_i

    ,input  logic [63:0]                csr_data_i

    ,output logic [PKT_W_p-1:0]         pkt_o
    ,output logic                       pkt_v_o
    ,output logic [PKT_SIZE_W_lp-1:0]   pkt_size_o
    ,input  logic                       pkt_ready_i
);

    // --- Internal Registers & State ---
    typedef enum logic [2:0] {
        S_IDLE,
        S_SEND_HDR,
        S_GATHER,
        S_SEND_DATA,
        S_DONE
    } st_e;

    st_e st_r, st_n;
    logic [PKT_W_p-1:0] buf_r, buf_n;
    logic [3:0]         pkt_cnt_r, pkt_cnt_n;

    // Captured command context
    logic               is_v16_r, is_m16_r, is_v8_r, is_m8_r, is_csr_r;
    logic [3:0]         total_pkts_r;
    logic [31:0]        hdr_flit_r;
    logic [PKT_SIZE_W_lp-1:0] data_pkt_size_r;
    logic [ADDR_W_lp-1:0]     base_row_r;

    // --- Combinational Logic ---
    assign ready_o     = (st_r == S_IDLE);
    assign rd_active_o = (st_r != S_IDLE);
    assign done_o      = (st_r == S_DONE);

    always_comb begin
        st_n      = st_r;
        buf_n     = buf_r;
        pkt_cnt_n = pkt_cnt_r;

        case (st_r)
            S_IDLE: if (v_i) begin
                pkt_cnt_n = '0;
                st_n      = S_SEND_HDR;
            end

            S_SEND_HDR: if (pkt_ready_i) begin
                st_n = is_csr_r ? S_SEND_DATA : S_GATHER;
            end

            S_GATHER: begin
                buf_n = '0;
                if (is_m16_r || is_v16_r) begin
                    buf_n = mem_data_i; // Full 256b
                end else begin
                    // Align 64b IFMAP data to the TOP of the packet
                    buf_n[PKT_W_p-1 -: 64] = mem_data_i[IFM_W_lp-1:0];
                end
                st_n = S_SEND_DATA;
            end

            S_SEND_DATA: if (pkt_ready_i) begin
                pkt_cnt_n = pkt_cnt_r + 1;
                if (pkt_cnt_n == total_pkts_r) st_n = S_DONE;
                else                           st_n = S_GATHER;
            end

            S_DONE: st_n = S_IDLE;
            default: st_n = S_IDLE;
        endcase
    end

    // --- Output Assignments ---
    assign mem_v_o    = (st_r == S_GATHER);
    assign mem_addr_o = base_row_r + ADDR_W_lp'(pkt_cnt_r);
    assign mem_bank_o = (is_v16_r || is_m16_r) ? BANK_PSUM : BANK_IFMAP;

    always_comb begin
        pkt_o      = '0;
        pkt_v_o    = 1'b0;
        pkt_size_o = '0;

        case (st_r)
            S_SEND_HDR: begin
                pkt_v_o    = 1'b1;
                // Header Flit at the top
                pkt_o[PKT_W_p-1 -: 32] = hdr_flit_r;
                pkt_size_o = PKT_SIZE_W_lp'(1);
            end
            S_SEND_DATA: begin
                pkt_v_o    = 1'b1;
                pkt_size_o = data_pkt_size_r;
                if (is_csr_r) begin
                    // Align CSR 64b to the top
                    pkt_o[PKT_W_p-1 -: 64] = csr_data_i;
                end else begin
                    pkt_o = buf_r;
                end
            end
            default: ;
        endcase
    end

    // --- Sequential Block ---
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            st_r <= S_IDLE;
            {buf_r, pkt_cnt_r, is_v16_r, is_m16_r, is_v8_r, is_m8_r, is_csr_r,
             total_pkts_r, data_pkt_size_r, hdr_flit_r, base_row_r} <= '0;
        end else begin
            st_r      <= st_n;
            buf_r     <= buf_n;
            pkt_cnt_r <= pkt_cnt_n;

            if (st_r == S_IDLE && v_i) begin
                is_v16_r     <= (cmd_i.op == OP_READV16);
                is_m16_r     <= (cmd_i.op == OP_READM16);
                is_v8_r      <= (cmd_i.op == OP_READV8);
                is_m8_r      <= (cmd_i.op == OP_READM8);
                is_csr_r     <= (cmd_i.op == OP_READ_CSR);
                base_row_r   <= ((cmd_i.op == OP_READV8) || (cmd_i.op == OP_READV16)) ?
                                 cmd_i.vaddr[ADDR_W_lp-1:0] : (cmd_i.baddr_src * DIM_p);

                // Pre-calculate packet loop counts
                total_pkts_r <= ((cmd_i.op == OP_READM8) || (cmd_i.op == OP_READM16)) ?
                                 DIM_p[3:0] : 4'd1;

                // Pre-calculate packet sizes
                if ((cmd_i.op == OP_READV8) || (cmd_i.op == OP_READM8) || (cmd_i.op == OP_READ_CSR))
                    data_pkt_size_r <= PKT_SIZE_W_lp'(2);
                else
                    data_pkt_size_r <= PKT_SIZE_W_lp'(8);

                // Pre-construct Header
                hdr_flit_r      <= '0;
                hdr_flit_r[5:0] <= cmd_i.op;
                if ((cmd_i.op == OP_READM8) || (cmd_i.op == OP_READM16))
                    hdr_flit_r[25:20] <= cmd_i.baddr_src << 3;
                if ((cmd_i.op == OP_READV8) || (cmd_i.op == OP_READV16))
                    hdr_flit_r[25:17] <= cmd_i.vaddr;
            end
        end
    end

endmodule
