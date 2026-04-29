module lvt_mem #(
    parameter ADDR_WIDTH_p = 9,
    parameter DATA_WIDTH_p = 128,
    localparam BANK_DEPTH_p = 1 << ADDR_WIDTH_p
)(
    input  logic                     clk_i,

    // 4 write ports
    input  logic [3:0]               we_i,
    input  logic [3:0][ADDR_WIDTH_p-1:0]   waddr_i,
    input  logic [3:0][DATA_WIDTH_p-1:0]   wdata_i,

    // 4 read ports
    input  logic [3:0][ADDR_WIDTH_p-1:0]   raddr_i,
    output logic [3:0][DATA_WIDTH_p-1:0]   rdata_o
);

    // ------------------------------------------------------------
    // 4 physical banks (1 write port each, multi-read via muxing)
    // ------------------------------------------------------------
    logic [DATA_WIDTH_p-1:0] bank [3:0][BANK_DEPTH_p-1:0];

    // ------------------------------------------------------------
    // Live Value Table (LVT): which bank holds the newest value
    // ------------------------------------------------------------
    logic [1:0] lvt [BANK_DEPTH_p-1:0];

    // ------------------------------------------------------------
    // WRITE LOGIC
    // Each write port writes only to its own bank.
    // LVT is updated to point to the last writer.
    // ------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        for (int i = 0; i < 4; i++) begin
            if (we_i[i]) begin
                bank[i][waddr_i[i]] <= wdata_i[i];
                lvt[waddr_i[i]]     <= i[1:0];
            end
        end
    end

    // ------------------------------------------------------------
    // READ LOGIC (synchronous)
    // 1-cycle latency.
    // Read-old behavior:
    // If a read and write hit the same address in the same cycle,
    // the read returns the OLD value (no forwarding).
    // ------------------------------------------------------------
    logic [1:0] owner_q [3:0];
    logic [ADDR_WIDTH_p-1:0] raddr_q [3:0];

    // Pipeline read address + owner
    always_ff @(posedge clk_i) begin
        for (int j = 0; j < 4; j++) begin
            raddr_q[j] <= raddr_i[j];
            owner_q[j] <= lvt[raddr_i[j]];
        end
    end

    // Read data from selected bank
    always_ff @(posedge clk_i) begin
        for (int j = 0; j < 4; j++) begin
            rdata_o[j] <= bank[owner_q[j]][raddr_q[j]];
        end
    end

endmodule