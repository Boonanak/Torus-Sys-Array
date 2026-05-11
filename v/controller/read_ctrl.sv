import ctrl_pkg::*;
import scratchpad_pkg::*;

module read_ctrl #(
     parameter int DIM_p            = scratchpad_pkg::DIM_p
    ,parameter int PKT_W_p          = scratchpad_pkg::PSM_ROW_W_lp
    ,parameter int FLIT_W_p         = 32
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

    // --- Command Decoding ---
    logic is_v8, is_v16, is_m8, is_m16, is_csr;
    always_comb begin
        is_v8  = (cmd_i.op == OP_READV8);
        is_v16 = (cmd_i.op == OP_READV16);
        is_m8  = (cmd_i.op == OP_READM8);
        is_m16 = (cmd_i.op == OP_READM16);
        is_csr = (cmd_i.op == OP_READ_CSR);
    end

    sp_bank_id_e bank_sel;
    always_comb begin
        if (is_v16 || is_m16)  bank_sel = BANK_PSUM;
        else                   bank_sel = BANK_IFMAP;
    end

    logic [ADDR_W_lp-1:0] base_row;
    always_comb begin
        if (is_v8 || is_v16) base_row = cmd_i.vaddr[ADDR_W_lp-1:0];
        else                 base_row = cmd_i.baddr_src * DIM_p;
    end

    // --- Loop Control ---
    // total_pkts defines how many times we cycle through GATHER -> SEND
    logic [3:0] total_pkts;
    always_comb begin
        if (is_csr || is_v8 || is_v16) total_pkts = 4'd1;
        else                           total_pkts = DIM_p[3:0]; // M8 and M16 read DIM_p rows
    end

    // pkt_size encoding for the data payload
    logic [PKT_SIZE_W_lp-1:0] data_pkt_size;
    always_comb begin
        if (is_v8 || is_m8 || is_csr) begin
            data_pkt_size = PKT_SIZE_W_lp'(2); // 64 bits = 2 flits
        end else begin 
            data_pkt_size = PKT_SIZE_W_lp'(8); // 256 bits = 8 flits (or 0 if encoded as full)
        end
    end

    // --- State Machine ---
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
    
    // Captured command state
    logic               is_v16_r, is_m16_r, is_v8_r, is_m8_r, is_csr_r;
    logic [3:0]         total_pkts_r;
    logic [31:0]        hdr_flit_r;
    logic [PKT_SIZE_W_lp-1:0] data_pkt_size_r;
    logic [ADDR_W_lp-1:0]     base_row_r;

    assign ready_o     = (st_r == S_IDLE);
    assign rd_active_o = (st_r != S_IDLE);
    assign done_o       = (st_r == S_DONE);

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
                if (is_csr_r) st_n = S_SEND_DATA;
                else          st_n = S_GATHER;
            end

            S_GATHER: begin
                // In the "1 row = 1 packet" model, we just grab the memory bus
                // We pad/align here so buf_r is always ready for pkt_o
                buf_n = '0;
                if (is_m16_r || is_v16_r) begin
                    buf_n = mem_data_i;
                end else begin
                    // V8 and M8: row is 64 bits
                    buf_n[63:0] = mem_data_i[IFM_W_lp-1:0];
                end
                st_n = S_SEND_DATA;
            end

            S_SEND_DATA: if (pkt_ready_i) begin
                pkt_cnt_n = pkt_cnt_r + 1;
                if (pkt_cnt_n == total_pkts_r) begin
                    st_n = S_DONE;
                end else begin
                    st_n = S_GATHER;
                end
            end

            S_DONE: st_n = S_IDLE;

            default: st_n = S_IDLE;
        endcase
    end

    // --- Physical Interfaces ---
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
                pkt_o      = {hdr_flit_r, {(PKT_W_p-32){1'b0}}};
                pkt_size_o = PKT_SIZE_W_lp'(1);
            end
            S_SEND_DATA: begin
                pkt_v_o    = 1'b1;
                pkt_size_o = data_pkt_size_r;
                if (is_csr_r) pkt_o[63:0] = csr_data_i;
                else          pkt_o       = buf_r;
            end
            default: ;
        endcase
    end

    // --- Sequential Logic ---
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            st_r            <= S_IDLE;
            buf_r           <= '0;
            pkt_cnt_r       <= '0;
            is_v16_r        <= '0;
            is_m16_r        <= '0;
            is_v8_r         <= '0;
            is_m8_r         <= '0;
            is_csr_r        <= '0;
            total_pkts_r    <= '0;
            data_pkt_size_r <= '0;
            hdr_flit_r      <= '0;
            base_row_r      <= '0;
        end else begin
            st_r      <= st_n;
            buf_r     <= buf_n;
            pkt_cnt_r <= pkt_cnt_n;
            
            if (st_r == S_IDLE && v_i) begin
                is_v16_r        <= is_v16;
                is_m16_r        <= is_m16;
                is_v8_r         <= is_v8;
                is_m8_r         <= is_m8;
                is_csr_r        <= is_csr;
                total_pkts_r    <= total_pkts;
                data_pkt_size_r <= data_pkt_size;
                base_row_r      <= base_row;
                
                // Header Flit Construction
                hdr_flit_r      <= '0;
                hdr_flit_r[5:0] <= cmd_i.op;
                if (is_m8 || is_m16) hdr_flit_r[25:20] <= cmd_i.baddr_src << 3;
                if (is_v8 || is_v16) hdr_flit_r[25:17] <= cmd_i.vaddr;
            end
        end
    end

endmodule