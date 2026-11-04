// uart_hex32_tx.sv
// Sends a 32-bit word to the PC as 8 hex characters followed by '\n'
// (9 bytes per word). Reusable: wire any 32-bit signal + a valid strobe to it.
//
// Handshake: when ready_o is high, pulse valid_i with data_i. The word is
// captured on that cycle, so data_i only needs to be stable for that cycle.
//
// NOTE: at 115200 baud one word takes ~0.78 ms. If you stream words faster
// than that (e.g. chip output at a fast clock), words arriving while
// ready_o is low must be buffered in a FIFO or they will be lost.
module uart_hex32_tx #(
     parameter int CLK_HZ = 50_000_000
    ,parameter int BAUD   = 115200
)(
     input  logic        clk_i
    ,input  logic        reset_i
    ,input  logic [31:0] data_i
    ,input  logic        valid_i
    ,output logic        ready_o
    ,output logic        tx_o
);

    typedef enum logic {IDLE, SEND} state_e;
    state_e state;

    logic [31:0] word_r;
    logic [3:0]  idx;          // 0..7 = hex digits, 8 = newline
    logic        uart_valid, uart_ready;
    logic [7:0]  ch;
    logic [3:0]  nib;

    function automatic logic [7:0] hex_ascii(input logic [3:0] n);
        if (n < 4'd10) hex_ascii = 8'h30 + {4'h0, n};
        else           hex_ascii = 8'h41 + {4'h0, n} - 8'd10;
    endfunction

    assign nib = word_r[(7 - idx) * 4 +: 4];
    assign ch  = (idx == 4'd8) ? 8'h0A : hex_ascii(nib);

    assign ready_o    = (state == IDLE);
    assign uart_valid = (state == SEND);

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            state  <= IDLE;
            idx    <= '0;
            word_r <= '0;
        end else begin
            case (state)
                IDLE: if (valid_i) begin
                    word_r <= data_i;
                    idx    <= '0;
                    state  <= SEND;
                end
                SEND: if (uart_valid && uart_ready) begin
                    if (idx == 4'd8) state <= IDLE;
                    else             idx   <= idx + 4'd1;
                end
            endcase
        end
    end

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart (
         .clk_i   (clk_i)
        ,.reset_i (reset_i)
        ,.data_i  (ch)
        ,.valid_i (uart_valid)
        ,.ready_o (uart_ready)
        ,.tx_o    (tx_o)
    );

endmodule
