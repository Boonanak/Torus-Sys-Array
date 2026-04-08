module instfifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH = 16,
    parameter PTR_WIDTH = $clog2(DEPTH) 
)(
    input  wire                   clk,
    input  wire                   rst, // Active high, synchronous reset
    input  wire                   wr_en,
    input  wire                   rd_en,
    input  wire [DATA_WIDTH-1:0]  wdata,
    output reg  [DATA_WIDTH-1:0]  rdata,
    output wire                   full,
    output wire                   empty,
    output wire                   almost_full,
    output wire                   almost_empty
);

    // 1. The Memory Array 
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // 2. The Pointers (Width is PTR_WIDTH + 1 to include MSB)
    reg [PTR_WIDTH:0] wr_ptr;
    reg [PTR_WIDTH:0] rd_ptr;
    wire do_read = rd_en && !empty;
    wire do_write = wr_en && (!full || do_read);

    // 3. Write Logic
    always @(posedge clk) begin
        if (rst) begin
            wr_ptr <= 0;
        end else if (do_write) begin
            mem[wr_ptr[PTR_WIDTH-1:0]] <= wdata; // Only use lower bits for memory address
            wr_ptr <= wr_ptr + 1;                // Wraps automatically
        end
    end

    // 4. Read Logic
    always @(posedge clk) begin
        if (rst) begin
            rd_ptr <= 0;
            rdata  <= 0;
        end else if (do_read) begin
            rdata <= mem[rd_ptr[PTR_WIDTH-1:0]];
            rd_ptr <= rd_ptr + 1;
        end
    end

    // 5. Flag Logic
    // Empty: Every single bit is identical.
    assign empty = (wr_ptr == rd_ptr);
    
    // Full: MSB is different, but all lower address bits are identical.
    assign full = (wr_ptr[PTR_WIDTH] != rd_ptr[PTR_WIDTH]) && 
                  (wr_ptr[PTR_WIDTH-1:0] == rd_ptr[PTR_WIDTH-1:0]);

    // 6. Bonus: Occupancy & Almost Flags 
    // How many items are currently in the FIFO?
    wire [PTR_WIDTH:0] fifo_count = wr_ptr - rd_ptr;
    
    // Let's set almost empty at 2 items, almost full at DEPTH-2.
    assign almost_empty = (fifo_count <= 2);
    assign almost_full  = (fifo_count >= (DEPTH - 2));

endmodule