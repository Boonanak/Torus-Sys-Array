// bringup_common.sv
// Helper modules shared by emu_top and board_top.
// Needs uart_tx.sv and uart_hex32_tx.sv (from the uart_debug folder) in the project.

// -----------------------------------------------------------------------
// clk_div: divide a clock by an even number. DIV <= 1 passes the clock through.
// NOTE: this makes a clock out of a register. Quartus will put it on a global
// clock network, but you must tell the Timing Analyzer about it (see the .sdc).
// -----------------------------------------------------------------------
module clk_div #(
    parameter int DIV = 4
)(
     input  logic clk_i
    ,output logic clk_o
);
    generate
        if (DIV <= 1) begin : g_pass
            assign clk_o = clk_i;
        end else begin : g_div
            localparam int HALF = DIV / 2;
            localparam int CW   = (HALF > 1) ? $clog2(HALF) : 1;
            logic [CW-1:0] cnt   = '0;
            logic          clk_r = 1'b0;
            always_ff @(posedge clk_i) begin
                if (cnt == HALF - 1) begin
                    cnt   <= '0;
                    clk_r <= ~clk_r;
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end
            assign clk_o = clk_r;
        end
    endgenerate
endmodule

// -----------------------------------------------------------------------
// rst_gen: synchronizes an asynchronous active-high reset (e.g. a button)
// into clk_i and also holds reset for POR_CYCLES cycles after power-up.
// -----------------------------------------------------------------------
module rst_gen #(
    parameter int POR_CYCLES = 16
)(
     input  logic clk_i
    ,input  logic rst_async_i
    ,output logic rst_o
);
    localparam int PW = $clog2(POR_CYCLES + 1);
    logic [1:0]    sync = 2'b11;
    logic [PW-1:0] por  = '0;

    always_ff @(posedge clk_i) begin
        sync <= {sync[0], rst_async_i};
        if (sync[1])                 por <= '0;
        else if (por != POR_CYCLES)  por <= por + 1'b1;
    end
    assign rst_o = sync[1] | (por != POR_CYCLES);
endmodule

// rst_slow.sv  --  reset for a clock domain whose clock may be slow or even stopped.
//
// Asserts ASYNCHRONOUSLY the moment rst_i (the 50 MHz-domain reset) goes high, so it does
// not need a slow-clock edge to take effect. Releases SYNCHRONOUSLY: rst_i must be low,
// then 2 clk_i edges to synchronize, then HOLD more clk_i edges so every synchronous
// reset in the domain sees several clock edges while reset is still asserted.
module rst_slow #(
    parameter int HOLD = 16
)(
     input  logic clk_i       // the slow (selected) clock
    ,input  logic rst_i       // active-high reset from the always-running 50 MHz domain
    ,output logic rst_o
);
    localparam int CW = $clog2(HOLD + 1);
    localparam [CW-1:0] HOLD_C = HOLD;     // HOLD at the counter's width
    logic [1:0]    sync = 2'b11;
    logic [CW-1:0] cnt  = '0;

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            sync <= 2'b11;
            cnt  <= '0;
        end else begin
            sync <= {sync[0], 1'b0};
            if (!sync[1] && cnt != HOLD_C) cnt <= cnt + 1'b1;
        end
    end

    assign rst_o = sync[1] | (cnt != HOLD_C);
endmodule

// -----------------------------------------------------------------------
// hex7seg: hex digit -> DE-series 7-segment pattern (segments are active low,
// bit order {g,f,e,d,c,b,a}).
// -----------------------------------------------------------------------
module hex7seg (
     input  logic [3:0] d_i
    ,output logic [6:0] seg_o
);
    always_comb begin
        case (d_i)
            4'h0: seg_o = 7'b1000000;
            4'h1: seg_o = 7'b1111001;
            4'h2: seg_o = 7'b0100100;
            4'h3: seg_o = 7'b0110000;
            4'h4: seg_o = 7'b0011001;
            4'h5: seg_o = 7'b0010010;
            4'h6: seg_o = 7'b0000010;
            4'h7: seg_o = 7'b1111000;
            4'h8: seg_o = 7'b0000000;
            4'h9: seg_o = 7'b0010000;
            4'hA: seg_o = 7'b0001000;
            4'hB: seg_o = 7'b0000011;
            4'hC: seg_o = 7'b1000110;
            4'hD: seg_o = 7'b0100001;
            4'hE: seg_o = 7'b0000110;
            default: seg_o = 7'b0001110;   // F
        endcase
    end
endmodule

// -----------------------------------------------------------------------
// flit_fifo: single-clock FIFO with a registered-read memory (maps onto block
// RAM). Read data is valid when rd_v_o is high; pop it by raising rd_ready_i
// in the same cycle. After a pop, rd_v_o drops for one cycle.
// overflow_o is sticky: set if a word arrives while the FIFO is full.
// -----------------------------------------------------------------------
module flit_fifo #(
     parameter int WIDTH  = 32
    ,parameter int ADDR_W = 9
)(
     input  logic             clk_i
    ,input  logic             rst_i
    ,input  logic             wr_v_i
    ,input  logic [WIDTH-1:0] wr_data_i
    ,input  logic             rd_ready_i
    ,output logic             rd_v_o
    ,output logic [WIDTH-1:0] rd_data_o
    ,output logic             overflow_o
);
    logic [WIDTH-1:0] mem [0:(1<<ADDR_W)-1];
    logic [ADDR_W:0]  wptr, rptr;
    logic [WIDTH-1:0] rd_data_q;
    logic             stable_q;

    wire empty = (wptr == rptr);
    wire full  = (wptr[ADDR_W-1:0] == rptr[ADDR_W-1:0]) && (wptr[ADDR_W] != rptr[ADDR_W]);
    wire pop   = rd_v_o && rd_ready_i;

    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            wptr       <= '0;
            rptr       <= '0;
            stable_q   <= 1'b0;
            overflow_o <= 1'b0;
        end else begin
            if (wr_v_i) begin
                if (full) overflow_o <= 1'b1;
                else      wptr       <= wptr + 1'b1;
            end
            if (pop) rptr <= rptr + 1'b1;
            // rd_data_q is only trustworthy if, on the previous edge, the FIFO
            // was non-empty and nothing was popped (the memory read is synchronous).
            stable_q <= ~empty && ~pop;
        end
    end

    // memory: one write port, one registered read port (no reset)
    always_ff @(posedge clk_i) begin
        if (wr_v_i && !full) mem[wptr[ADDR_W-1:0]] <= wr_data_i;
        rd_data_q <= mem[rptr[ADDR_W-1:0]];
    end

    assign rd_v_o    = stable_q;
    assign rd_data_o = rd_data_q;
endmodule

// -----------------------------------------------------------------------
// bringup_io: everything between the driver's status outputs and the board.
//   LEDR[0] done          LEDR[1] error (sticky, from the trace player)
//   LEDR[2] parity error seen (sticky)   LEDR[3] UART FIFO overflowed
//   LEDR[4] chip has sent at least one flit   LEDR[5] timeout
//   LEDR[6] trace_enable_i (essentially confirmation the reset sequence has finished)
//   LEDR[9] heartbeat (clock is alive)
//   HEX5..HEX3 = send trace address [11:0],  HEX2..HEX0 = recv trace address [11:0]
//   uart_tx_o  = every flit from the chip as 8 hex chars + newline
// All of it runs in clk_i's domain, so there is no clock crossing.
// -----------------------------------------------------------------------
module bringup_io #(
     parameter int CLK_HZ         = 12_500_000
    ,parameter int BAUD           = 115200
    ,parameter int FIFO_ADDR_W    = 9
    ,parameter int HB_BIT         = 23
    ,parameter int TIMEOUT_CYCLES = CLK_HZ * 10   // ~10 s at 12.5 MHz
)(
     input  logic        clk_i
    ,input  logic        rst_i
    ,input  logic        run_i
    // status from the driver
    ,input  logic        trace_ready_i
    ,input  logic        done_i
    ,input  logic        error_i
    ,input  logic        parity_err_i
    ,input  logic [31:0] send_addr_i
    ,input  logic [31:0] recv_addr_i
    ,input  logic        out_valid_i
    ,input  logic [31:0] out_data_i
    // to the board
    ,output logic [9:0]  ledr_o
    ,output logic [6:0]  hex0_o, hex1_o, hex2_o, hex3_o, hex4_o, hex5_o
    ,output logic        uart_tx_o
);

    // ---- sticky flags + heartbeat + timeout ----
    logic        parity_seen, out_seen, timeout_seen, fifo_overflow;
    logic [31:0] hb_cnt = 32'd0;
    logic [31:0] to_cnt;

    always_ff @(posedge clk_i) begin
        hb_cnt <= hb_cnt + 1'b1;
        if (rst_i) begin
            parity_seen  <= 1'b0;
            out_seen     <= 1'b0;
            timeout_seen <= 1'b0;
            to_cnt       <= '0;
        end else begin
            if (parity_err_i) parity_seen <= 1'b1;
            if (out_valid_i)  out_seen    <= 1'b1;
            if (run_i && !done_i) begin
                if (to_cnt == TIMEOUT_CYCLES) timeout_seen <= 1'b1;
                else                          to_cnt       <= to_cnt + 1'b1;
            end
        end
    end

    assign ledr_o = {hb_cnt[HB_BIT], rst_i, run_i, trace_ready_i, timeout_seen, out_seen,
                     fifo_overflow, parity_seen, error_i, done_i};

    // ---- seven-segment displays ----
    hex7seg u_h0 (.d_i(recv_addr_i[3:0]),  .seg_o(hex0_o));
    hex7seg u_h1 (.d_i(recv_addr_i[7:4]),  .seg_o(hex1_o));
    hex7seg u_h2 (.d_i(recv_addr_i[11:8]), .seg_o(hex2_o));
    hex7seg u_h3 (.d_i(send_addr_i[3:0]),  .seg_o(hex3_o));
    hex7seg u_h4 (.d_i(send_addr_i[7:4]),  .seg_o(hex4_o));
    hex7seg u_h5 (.d_i(send_addr_i[11:8]), .seg_o(hex5_o));

    // ---- flits from the chip -> FIFO -> UART ----
    logic        fifo_v, uart_ready;
    logic [31:0] fifo_data;

    flit_fifo #(.WIDTH(32), .ADDR_W(FIFO_ADDR_W)) u_fifo (
         .clk_i      (clk_i)
        ,.rst_i      (rst_i)
        ,.wr_v_i     (out_valid_i)
        ,.wr_data_i  (out_data_i)
        ,.rd_ready_i (uart_ready)
        ,.rd_v_o     (fifo_v)
        ,.rd_data_o  (fifo_data)
        ,.overflow_o (fifo_overflow)
    );

    uart_hex32_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart (
         .clk_i   (clk_i)
        ,.reset_i (rst_i)
        ,.data_i  (fifo_data)
        ,.valid_i (fifo_v)
        ,.ready_o (uart_ready)
        ,.tx_o    (uart_tx_o)
    );

endmodule
