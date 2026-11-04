// uart_tx.sv
// Minimal 8N1 UART transmitter (1 start bit, 8 data bits LSB first, 1 stop bit).
// Handshake: when ready_o is high, pulse valid_i with data_i to send one byte.
module uart_tx #(
     parameter int CLK_HZ = 50_000_000
    ,parameter int BAUD   = 115200
)(
     input  logic       clk_i
    ,input  logic       reset_i
    ,input  logic [7:0] data_i
    ,input  logic       valid_i
    ,output logic       ready_o
    ,output logic       tx_o
);

    localparam int CLKS_PER_BIT = CLK_HZ / BAUD;

    logic [$clog2(CLKS_PER_BIT)-1:0] clk_cnt;
    logic [3:0] bit_idx;     // 0 = start, 1..8 = data, 9 = stop
    logic [9:0] shreg;       // {stop, d7..d0, start}
    logic       busy;

    assign ready_o = ~busy;

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            busy    <= 1'b0;
            tx_o    <= 1'b1;   // line idles high
            clk_cnt <= '0;
            bit_idx <= '0;
            shreg   <= '1;
        end else if (!busy) begin
            tx_o <= 1'b1;
            if (valid_i) begin
                shreg   <= {1'b1, data_i, 1'b0};
                busy    <= 1'b1;
                clk_cnt <= '0;
                bit_idx <= '0;
                tx_o    <= 1'b0;   // start bit begins immediately
            end
        end else begin
            if (clk_cnt == CLKS_PER_BIT - 1) begin
                clk_cnt <= '0;
                if (bit_idx == 4'd9) begin
                    busy <= 1'b0;          // stop bit finished
                    tx_o <= 1'b1;
                end else begin
                    bit_idx <= bit_idx + 4'd1;
                    tx_o    <= shreg[bit_idx + 4'd1];
                end
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
            end
        end
    end

endmodule
