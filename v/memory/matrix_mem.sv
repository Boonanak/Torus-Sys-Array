// Implments a 1 read 1 write port memory with async read and sync write
// Designed to store vectors for sets of matricies
module matrix_mem #( parameter WIDTH_p = 64, // Width of the individual vectors
                     parameter DIM_p = 8,   // Grouping of vectors (how many vectors make up a single matrix)
                     parameter ENTRIES_p = 64 // Number of matrices
                     localparam NUM_ADDRESSES_lp = DIM_p * ENTRIES_p; // Number of address in the memory
                     localparam ADDRESS_WIDTH_lp = $clog2(NUM_ADDRESSES_lp); // minimum bitwidth required to store NUM_ADDRESSES_lp
                   ) (
                     input logic clk_i,
                     input logic reset_n_i,
                     input logic wren,
                     input logic  [ADDRESS_WIDTH_lp-1:0] rd_addr,
                     input logic  [ADDRESS_WIDTH_lp-1:0] wr_addr, 
                     input logic  [WIDTH_P-1:0] wr_data,
                     output logic [WIDTH_P-1:0] rd_data
                   );

    logic [WIDTH_P-1:0] mem [NUM_ADDRESSES_lp-1:0]; // Memory Array

    always_ff @(posedge clk_i) begin
        if (wren)
            mem[wr_addr] <= wr_data;
    end

    assign rd_data = mem[rd_addr];

endmodule 