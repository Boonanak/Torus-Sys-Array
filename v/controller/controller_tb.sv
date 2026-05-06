
`timescale 1ns / 1ps

module controller_tb;

    import ctrl_pkg::*;
    import scratchpad_pkg::*;
    import PE_pkg::*;

    initial begin 
        $fsdbDumpfile("waveform.fsdb");
        $fsdbDumpvars("+all");
    end

    // --- Parameters ---
    parameter int DIM_p           = 8;
    parameter int NUM_MATRICES_p  = 8;
    parameter int SEND_RING_WIDTH_lp   = 128;
    parameter int RECV_RING_WIDTH_lp   = 512;
    
    localparam int ADDR_W_lp      = $clog2(NUM_MATRICES_p * DIM_p);
    localparam int IFM_W_lp       = DIM_p * 8;
    localparam int WGT_W_lp       = DIM_p * 8;
    localparam int PSM_W_lp       = DIM_p * 32;

    logic clk_i;
    bsg_nonsynth_clock_gen #(.cycle_time_p(12000)) clk_gen (clk_i);

    logic reset_i;
    bsg_nonsynth_reset_gen #(.num_clocks_p(1), .reset_cycles_lo_p(5), .reset_cycles_hi_p(5))
        reset_gen (.clk_i(clk_i), .async_reset_o(reset_i));

    // --- Trace Signals ---
    logic tr_v_lo, tr_yumi_li;
    logic [SEND_RING_WIDTH_lp-1:0] tr_data_lo;
    logic [RECV_RING_WIDTH_lp-1:0] dut_data_r;
    logic dut_v_r, tr_ready_lo;

    logic [31:0] rom_addr_li;
    logic [SEND_RING_WIDTH_lp+3:0] rom_data_send;
    logic [RECV_RING_WIDTH_lp+3:0] rom_data_recv;
    logic done_send, done_recv;

    // --- Interconnect Wires ---
    // Instruction Bus
    decoded_cmd_t q_cmd;
    logic q_cmd_v, q_cmd_ready;

    // Internal Controller Handshakes
    decoded_cmd_t wr_cmd, rd_cmd, ex_cmd, cs_cmd;
    logic wr_v, rd_v, ex_v, cs_v;
    logic wr_ready, rd_ready, ex_ready, cs_ready;
    logic wr_done, rd_done, ex_done, cs_done;

    // Execute Controller Specifics
    logic ex_active;
    logic ex_ifm_r_v, ex_wgt_r_v, ex_psm_r_v;
    logic [ADDR_W_lp-1:0] ex_ifm_r_addr, ex_wgt_r_addr, ex_psm_r_addr;
    logic [IFM_W_lp-1:0]  ex_ifm_r_data;
    logic [WGT_W_lp-1:0]  ex_wgt_r_data;
    logic [PSM_W_lp-1:0]  ex_psm_r_data;
    logic ex_psm_w_v, ex_ifm_w_v;
    logic [ADDR_W_lp-1:0] ex_psm_w_addr, ex_ifm_w_addr;
    logic [PSM_W_lp-1:0]  ex_psm_w_data;
    logic [IFM_W_lp-1:0]  ex_ifm_w_data;

    // Write/Read Controller Specifics
    logic wr_mem_v, rd_mem_v, rd_active;
    logic [ADDR_W_lp-1:0] wr_mem_addr, rd_mem_addr;
    logic [PSM_W_lp-1:0]  wr_mem_data, rd_mem_data;
    sp_bank_id_e wr_mem_bank, rd_mem_bank;

    // Sideband & Execution
    mesh_req_t mreq;
    logic mreq_v, mreq_ready, mreq_done;
    logic tp_in_valid, tp_out_valid, tp_transpose, tp_in_ready, tp_out_ready;
    logic mem_conflict, ex_transpose_conflict;

    // dummy inputs from transposer and mesh into exec_ctrl (execution results)
    logic signed [7:0] tp_out_data_zero [DIM_p-1:0];
    logic signed [18:0] mesh_psum_row_zero [DIM_p-1:0];

    // Initialize transposer/mesh output and handshake
    assign tp_out_valid = '1;
    assign tp_in_ready = '1;
    assign mreq_ready = '1;
    assign mreq_done = '1;
    assign tp_out_data_zero = '{default: '0};
    assign mesh_psum_row_zero = '{default: '0};


    // --- Trace Replay Engines ---
    bsg_fsb_node_trace_replay #(.ring_width_p(SEND_RING_WIDTH_lp)
                               ,.rom_addr_width_p(32)
    ) trace_replay_send (
        .clk_i(~clk_i), .reset_i(reset_i), .en_i(1'b1),
        .v_i(1'b0), .data_i('0), .ready_o(), 
        .v_o(tr_v_lo), .data_o(tr_data_lo), .yumi_i(tr_yumi_li),
        .rom_addr_o(rom_addr_li), .rom_data_i(rom_data_send),
        .done_o(done_send), .error_o()
    );


    // fake dut_v_r for non rigorous testing for now, so we can see the simulation going.
    logic fake_dut_v_r;
    assign fake_dut_v_r = '0;

    bsg_fsb_node_trace_replay #(.ring_width_p(RECV_RING_WIDTH_lp)
                               ,.rom_addr_width_p(32)
    ) trace_replay_recv (
        .clk_i(~clk_i), .reset_i(reset_i), .en_i(1'b1),
        .v_i(fake_dut_v_r), .data_i(dut_data_r), .ready_o(tr_ready_lo),
        .v_o(), .data_o(), .yumi_i(1'b0),
        .rom_addr_o(), .rom_data_i(rom_data_recv),
        .done_o(done_recv), .error_o()
    );

    // --- Mapping ---
    assign q_cmd      = tr_data_lo[$bits(decoded_cmd_t)-1:0];
    assign q_cmd_v    = tr_v_lo;
    assign tr_yumi_li = q_cmd_v & q_cmd_ready;

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            dut_v_r <= 0;
            dut_data_r <= '0;
        end else begin
            // Pulse monitor on any controller activity
            dut_v_r <= wr_v | rd_v | ex_v | mreq_v | tp_in_valid;
            
            // Concatenate ALL ports for the receive trace comparison
            dut_data_r <= {
                // Status/Errors
                mem_conflict, ex_transpose_conflict, ex_active, rd_active,
                // Transposer
                tp_in_valid, tp_out_valid, tp_transpose, tp_in_ready, tp_out_ready,
                // Mesh Driver
                mreq_v, mreq_ready, mreq_done, mreq,
                // Memory Arbiter Inputs (Detailed)
                ex_ifm_r_v, ex_wgt_r_v, ex_psm_r_v, ex_psm_w_v, ex_ifm_w_v,
                ex_ifm_r_addr, ex_wgt_r_addr, ex_psm_r_addr, ex_psm_w_addr, ex_ifm_w_addr,
                wr_mem_v, wr_mem_addr, wr_mem_bank,
                rd_mem_v, rd_mem_addr, rd_mem_bank,
                // Command Echo
                q_cmd.op, q_cmd.baddr_dest
            };
            if (dut_v_r) begin 
                $display("dut_data_r: %h",dut_data_r);
            end
        end
    end

    // --- Full Module Instantiations ---

    dispatch u_disp (
        .clk_i, .reset_i,
        .cmd_i(q_cmd), .cmd_v_i(q_cmd_v), .cmd_ready_o(q_cmd_ready),
        .wr_cmd_o(wr_cmd), .wr_v_o(wr_v), .wr_ready_i(wr_ready), .wr_done_i(wr_done),
        .rd_cmd_o(rd_cmd), .rd_v_o(rd_v), .rd_ready_i(rd_ready), .rd_done_i(rd_done),
        .ex_cmd_o(ex_cmd), .ex_v_o(ex_v), .ex_ready_i(ex_ready), .ex_done_i(ex_done),
        .cs_cmd_o(cs_cmd), .cs_v_o(cs_v), .cs_ready_i(cs_ready), .cs_done_i(cs_done)
    );

    write_ctrl #(.DIM_p(DIM_p), .NUM_MATRICES_p(NUM_MATRICES_p)) u_wr (
        .clk_i, .reset_i,
        .cmd_i(wr_cmd), .v_i(wr_v), .ready_o(wr_ready), .done_o(wr_done),
        .mem_v_o(wr_mem_v), .mem_addr_o(wr_mem_addr), .mem_data_o(wr_mem_data), .mem_bank_o(wr_mem_bank)
    );

    read_ctrl #(.DIM_p(DIM_p), .NUM_MATRICES_p(NUM_MATRICES_p)) u_rd (
        .clk_i, .reset_i,
        .cmd_i(rd_cmd), .v_i(rd_v), .ready_o(rd_ready), .done_o(rd_done),
        .rd_active_o(rd_active),
        .mem_v_o(rd_mem_v), .mem_addr_o(rd_mem_addr), .mem_bank_o(rd_mem_bank), .mem_data_i(rd_mem_data),
        .csr_data_i(64'b0), .pkt_o(), .pkt_v_o(), .pkt_size_o(), .pkt_ready_i(1'b1)
    );

    exec_ctrl #(.DIM_p(DIM_p), .NUM_MATRICES_p(NUM_MATRICES_p)) u_ex (
        .clk_i, .reset_i,
        .cmd_i(ex_cmd), .v_i(ex_v), .ready_o(ex_ready), .done_o(ex_done),
        .ex_active_o(ex_active),
        .ifm_r_v_o(ex_ifm_r_v), .ifm_r_addr_o(ex_ifm_r_addr), .ifm_r_data_i(ex_ifm_r_data),
        .wgt_r_v_o(ex_wgt_r_v), .wgt_r_addr_o(ex_wgt_r_addr), .wgt_r_data_i(ex_wgt_r_data),
        .psm_r_v_o(ex_psm_r_v), .psm_r_addr_o(ex_psm_r_addr), .psm_r_data_i(ex_psm_r_data),
        .psm_w_v_o(ex_psm_w_v), .psm_w_addr_o(ex_psm_w_addr), .psm_w_data_o(ex_psm_w_data),
        .ifm_w_v_o(ex_ifm_w_v), .ifm_w_addr_o(ex_ifm_w_addr), .ifm_w_data_o(ex_ifm_w_data),
        .tp_in_data_o(), .tp_in_valid_o(tp_in_valid), .tp_transpose_o(tp_transpose),
        .tp_out_ready_o(tp_out_ready), .tp_in_ready_i(tp_in_ready), .tp_out_valid_i(tp_out_valid),
        .tp_out_data_i(tp_out_data_zero),
        .mreq_o(mreq), .mreq_v_o(mreq_v), .mreq_ready_i(mreq_ready), .mreq_done_i(mreq_done),
        .mesh_ifmap_row_o(), .mesh_weight_row_o(), .mesh_bias_row_o(),
        .mesh_cycle_i('0), .mesh_cycle_v_i(1'b0), .mesh_psum_row_i(mesh_psum_row_zero),
        .mesh_capture_v_i(1'b0), .mesh_capture_idx_i('0),
        .transpose_conflict_o(ex_transpose_conflict)
    );

    mem_arbiter #(.DIM_p(DIM_p), .NUM_MATRICES_p(NUM_MATRICES_p)) u_marb (
        .clk_i, .reset_i,
        .ex_active_i(ex_active),
        .ex_ifm_r_v_i(ex_ifm_r_v), .ex_ifm_r_addr_i(ex_ifm_r_addr), .ex_ifm_r_data_o(ex_ifm_r_data),
        .ex_wgt_r_v_i(ex_wgt_r_v), .ex_wgt_r_addr_i(ex_wgt_r_addr), .ex_wgt_r_data_o(ex_wgt_r_data),
        .ex_psm_r_v_i(ex_psm_r_v), .ex_psm_r_addr_i(ex_psm_r_addr), .ex_psm_r_data_o(ex_psm_r_data),
        .ex_psm_w_v_i(ex_psm_w_v), .ex_psm_w_addr_i(ex_psm_w_addr), .ex_psm_w_data_i(ex_psm_w_data),
        .ex_ifm_w_v_i(ex_ifm_w_v), .ex_ifm_w_addr_i(ex_ifm_w_addr), .ex_ifm_w_data_i(ex_ifm_w_data),
        .wr_v_i(wr_mem_v), .wr_addr_i(wr_mem_addr), .wr_data_i(wr_mem_data), .wr_bank_i(wr_mem_bank),
        .rd_v_i(rd_mem_v), .rd_addr_i(rd_mem_addr), .rd_bank_i(rd_mem_bank), .rd_data_o(rd_mem_data),
        .ifm_w_v_o(), .ifm_w_addr_o(), .ifm_w_data_o(),
        .ifm_r_v_o(), .ifm_r_addr_o(), .ifm_r_data_i('0),
        .wgt_w_v_o(), .wgt_w_addr_o(), .wgt_w_data_o(),
        .wgt_r_v_o(), .wgt_r_addr_o(), .wgt_r_data_i('0),
        .psm_w_v_o(), .psm_w_addr_o(), .psm_w_data_o(),
        .psm_r_v_o(), .psm_r_addr_o(), .psm_r_data_i('0),
        .mem_conflict_o(mem_conflict)
    );

    // --- Trace ROMs ---
    controller_send_trace_rom #(.width_p(SEND_RING_WIDTH_lp+4),.addr_width_p(32)) 
        ROM_send (
            .addr_i(rom_addr_li),
            .data_o(rom_data_send)
        );
    controller_recv_trace_rom #(.width_p(RECV_RING_WIDTH_lp+4),.addr_width_p(32))
        ROM_recv (
            .addr_i(rom_addr_li), 
            .data_o(rom_data_recv)
        );

    always @(posedge clk_i) if (done_send && done_recv) $finish;

endmodule
