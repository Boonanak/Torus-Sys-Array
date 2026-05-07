
import ctrl_pkg::*;
import scratchpad_pkg::*;

module read_ctrl #(
     parameter int DIM_p            = scratchpad_pkg::DIM_p
    ,parameter int PKT_W_p          = scratchpad_pkg::PSM_ROW_W_lp      // packet width is matched to widest
    ,parameter int FLIT_W_p         = 32                                       // T2SA-CTRL: depacketizer flit width (used to size pkt_size_o)
    ,localparam int ADDR_W_lp       = scratchpad_pkg::BANK_ADDR_W_IFM_lp
    ,localparam int IFM_W_lp        = scratchpad_pkg::IFM_ROW_W_lp
    ,localparam int PSM_W_lp        = scratchpad_pkg::PSM_ROW_W_lp
    ,localparam int CYC_W_lp  = $clog2(DIM_p+1)
    ,localparam int PKT_SIZE_W_lp = $clog2(PKT_W_p / FLIT_W_p)                 // T2SA-CTRL: 2b for 128b/4-flit, 3b for 256b/8-flit; "0=full" encoding
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
    ,input  logic [PSM_W_lp-1:0]        mem_data_i  // widest path

    ,input  logic [63:0]                csr_data_i

    ,output logic [PKT_W_p-1:0]         pkt_o
    ,output logic                       pkt_v_o
    // ,output logic [1:0]                 pkt_size_o                          // original: 2b (4-flit packets only)
    ,output logic [PKT_SIZE_W_lp-1:0]   pkt_size_o                             // T2SA-CTRL: width tracks PKT_W_p/FLIT_W_p (3b for 256b/8-flit)
    ,input  logic                       pkt_ready_i
);

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
        else                    bank_sel = BANK_IFMAP;  // V8/M8 read int8 (mirrored)
    end

    logic [ADDR_W_lp-1:0] base_row;
    always_comb begin
        if (is_v8 || is_v16) base_row = cmd_i.vaddr[ADDR_W_lp-1:0];
        else                  base_row = cmd_i.baddr_src * DIM_p;
    end

    logic [CYC_W_lp-1:0] rows_to_read;
    always_comb begin
        if (is_csr)                          rows_to_read = '0;
        else if (is_m8 || is_m16)            rows_to_read = DIM_p[CYC_W_lp-1:0];
        else                                  rows_to_read = 1;
    end

    logic [3:0] total_pkts;  // enough for 0..15
    // logic [1:0] data_pkt_size;                                              // original 2-bit
    logic [PKT_SIZE_W_lp-1:0] data_pkt_size;                                   // T2SA-CTRL: width tracks PKT_W_p/FLIT_W_p
    always_comb begin
        if (is_v8 || is_csr) begin
            total_pkts    = 1;
            // data_pkt_size = 2'd2;  // 64b payload
            data_pkt_size = PKT_SIZE_W_lp'(2);                                 // T2SA-CTRL: 64b = 2 flits
        end else if (is_v16) begin
            total_pkts    = 1;
            // data_pkt_size = 2'd0;  // 128b (size-4 encoded as 0)
            data_pkt_size = PKT_SIZE_W_lp'(4);                                 // T2SA-CTRL: 128b = 4 flits (PKT_W=128 wraps to 0=full; PKT_W=256 emits 4)
        end else if (is_m8) begin
            total_pkts    = (DIM_p + 1) / 2;
            // data_pkt_size = 2'd0;
            data_pkt_size = PKT_SIZE_W_lp'(4);                                 // T2SA-CTRL: 128b/pkt = 4 flits
        end else begin // m16
            total_pkts    = DIM_p[3:0];
            // data_pkt_size = 2'd0;
            data_pkt_size = PKT_SIZE_W_lp'(4);                                 // T2SA-CTRL: 128b/pkt = 4 flits
        end
    end

    logic [31:0] hdr_flit;
    always_comb begin
        hdr_flit = '0;
        hdr_flit[5:0] = cmd_i.op;
        if (is_m8 || is_m16) hdr_flit[25:20] = cmd_i.baddr_src;
        if (is_v8 || is_v16) hdr_flit[25:17] = cmd_i.vaddr;
    end

    localparam int BUF_W_lp = DIM_p * 128;  // worst case 8 × 128b
    logic [BUF_W_lp-1:0] buf_r, buf_n;

    logic [CYC_W_lp-1:0] row_cnt_r, row_cnt_n;
    logic [3:0]          pkt_cnt_r, pkt_cnt_n;

    logic                is_v8_r, is_v16_r, is_m8_r, is_m16_r, is_csr_r;
    logic [3:0]          total_pkts_r;
    // logic [1:0]          data_pkt_size_r;                                   // original 2-bit
    logic [PKT_SIZE_W_lp-1:0] data_pkt_size_r;                                 // T2SA-CTRL: width tracks PKT_W_p/FLIT_W_p
    logic [31:0]         hdr_flit_r;

    typedef enum logic [2:0] {
        S_IDLE, S_GATHER, S_SEND_HDR, S_SEND_DATA, S_DONE
    } st_e;
    st_e st_r, st_n;

    assign ready_o     = (st_r == S_IDLE);
    assign rd_active_o = (st_r != S_IDLE);

    function automatic logic [PSM_W_lp-1:0] psum_row_pad(input logic [PSM_W_lp-1:0] r);
        logic [PSM_W_lp-1:0] v;
        v = '0;
        v[PSM_W_lp-1:0] = r;  // already 16b/elem
        return v;
    endfunction

    always_comb begin
        st_n            = st_r;
        buf_n           = buf_r;
        row_cnt_n       = row_cnt_r;
        pkt_cnt_n       = pkt_cnt_r;

        case (st_r)
            S_IDLE: if (v_i) begin
                buf_n     = '0;
                row_cnt_n = '0;
                pkt_cnt_n = '0;
                if (is_csr)              st_n = S_SEND_HDR;  // skip gather
                else if (rows_to_read==0)st_n = S_SEND_HDR;  // safety
                else                      st_n = S_GATHER;
            end

            S_GATHER: begin
                if (is_m16_r || is_v16_r) begin
                    buf_n[row_cnt_r*PSM_W_lp +: PSM_W_lp] =
                        psum_row_pad(mem_data_i);
                end else begin
                    buf_n[row_cnt_r*64 +: 64] = mem_data_i[IFM_W_lp-1:0];
                end
                if (row_cnt_r == rows_to_read - 1) begin
                    st_n      = S_SEND_HDR;
                    row_cnt_n = '0;
                end else begin
                    row_cnt_n = row_cnt_r + 1;
                end
            end

            S_SEND_HDR: if (pkt_ready_i) begin
                st_n      = S_SEND_DATA;
                pkt_cnt_n = '0;
            end

            S_SEND_DATA: if (pkt_ready_i) begin
                if (pkt_cnt_r == total_pkts_r - 1) begin
                    st_n = S_DONE;
                end else begin
                    pkt_cnt_n = pkt_cnt_r + 1;
                end
            end

            S_DONE: st_n = S_IDLE;

            default: st_n = S_IDLE;
        endcase
    end

    assign mem_v_o    = (st_r == S_GATHER);
    assign mem_addr_o = base_row + row_cnt_r;  // base captured below via stored cmd
    assign mem_bank_o = bank_sel;

    logic [PKT_W_p-1:0] hdr_pkt;
    assign hdr_pkt = {hdr_flit_r, 96'b0};  // header in top flit

    logic [PKT_W_p-1:0] data_pkt;
    always_comb begin
        data_pkt = '0;
        if (is_csr_r) begin
            data_pkt[PKT_W_p-1 -: 64] = csr_data_i;
        end else if (is_v8_r) begin
            data_pkt[PKT_W_p-1 -: 64] = buf_r[63:0];
        end else if (is_v16_r) begin
            data_pkt = buf_r[127:0];
        end else if (is_m8_r) begin
            // TODO: data_pkt[255:128] might need to be set in same manner? check in simulation
            data_pkt[127:64] = buf_r[(pkt_cnt_r*128)     +: 64];  // row 2k
            data_pkt[63:0]   = buf_r[(pkt_cnt_r*128)+64  +: 64];  // row 2k+1
        end else begin // m16
            data_pkt = buf_r[pkt_cnt_r*128 +: 128];
        end
    end

    always_comb begin
        pkt_o      = '0;
        // pkt_size_o = 2'd0;  // "size 0" = full 4 flits
        pkt_size_o = '0;                                                       // T2SA-CTRL: default (only meaningful when pkt_v_o=1; 0 = full encoding)
        pkt_v_o    = 1'b0;
        case (st_r)
            S_SEND_HDR: begin
                pkt_o      = hdr_pkt;
                // pkt_size_o = 2'd1;  // 1 valid flit
                pkt_size_o = PKT_SIZE_W_lp'(1);                                // T2SA-CTRL: header = 1 flit
                pkt_v_o    = 1'b1;
            end
            S_SEND_DATA: begin
                pkt_o      = data_pkt;
                pkt_size_o = data_pkt_size_r;
                pkt_v_o    = 1'b1;
            end
            default: ;
        endcase
    end

    assign done_o = (st_r == S_DONE);

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            st_r            <= S_IDLE;
            buf_r           <= '0;
            row_cnt_r       <= '0;
            pkt_cnt_r       <= '0;
            is_v8_r         <= 1'b0;
            is_v16_r        <= 1'b0;
            is_m8_r         <= 1'b0;
            is_m16_r        <= 1'b0;
            is_csr_r        <= 1'b0;
            total_pkts_r    <= '0;
            data_pkt_size_r <= '0;
            hdr_flit_r      <= '0;
        end else begin
            st_r            <= st_n;
            buf_r           <= buf_n;
            row_cnt_r       <= row_cnt_n;
            pkt_cnt_r       <= pkt_cnt_n;
            if (st_r == S_IDLE && v_i) begin
                is_v8_r         <= is_v8;
                is_v16_r        <= is_v16;
                is_m8_r         <= is_m8;
                is_m16_r        <= is_m16;
                is_csr_r        <= is_csr;
                total_pkts_r    <= total_pkts;
                data_pkt_size_r <= data_pkt_size;
                hdr_flit_r      <= hdr_flit;
            end
        end
    end

endmodule
