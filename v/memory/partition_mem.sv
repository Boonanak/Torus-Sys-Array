// Memory with partionable write enables for each vector chunk. 
// Allows writing to only specific vectorized chunks of a given address.
// Supports arbitrary number of partitions per row, and arbitrary vector widths.
// Synchronous read and write.
module partition_mem #(parameter VECTOR_WIDTH_p = 64, // Default is 128 bit vectors split into 2 chunks, with 256 vectors (4KB total)
                    parameter VECTORS_PER_ROW_p = 2,
                    parameter NUM_VECTORS_p = 64,
                    localparam ROW_WIDTH_lp = VECTOR_WIDTH_p * VECTORS_PER_ROW_p,
                    localparam ADDRESS_BIT_WIDTH_lp = $clog2(NUM_VECTORS_p)
                   ) (
                    input logic clk_i,
                    input logic reset,
                    input logic [ADDRESS_BIT_WIDTH_lp-1:0] read_addr_i,
                    input logic [ADDRESS_BIT_WIDTH_lp-1:0] write_addr_i,
                    input [VECTORS_PER_ROW_p-1:0] wren_i, // multi-bit wren for write-masking
                    input logic [ROW_WIDTH_lp-1:0] write_data_i,
                    output logic [ROW_WIDTH_lp-1:0] read_data_o
                   );

    // Memory array
    logic [ROW_WIDTH_lp-1:0] mem_array [NUM_VECTORS_p-1:0];

    always_ff @(posedge clk_i) begin
        if (reset) begin 
            for (int i = 0; i < VECTORS_PER_ROW_p; i++) begin 
                mem_array[i] <= '0;
            end
        end

        for (int i = 0; i < VECTORS_PER_ROW_p; i++) begin
            if (wren_i[i]) begin
                // Magic bit masking
                // Write to a specific line at write address, but only write VECTOR_WIDTH bits if wren for that chunk.
                // if wren is 2 bits, and = 2'b10, only write VECTOR_WIDTH bits into the first half of mem[addr], and leave the second half unchanged.
                mem_array[write_addr_i][(i+1)*VECTOR_WIDTH_p-1 -: VECTOR_WIDTH_p] <= write_data_i[(i+1)*VECTOR_WIDTH_p-1 -: VECTOR_WIDTH_p];
            end
        end
        read_data_o <= mem_array[read_addr_i];
    end

endmodule