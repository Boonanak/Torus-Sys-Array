module partition_mem #(
    parameter VECTOR_WIDTH_p = 64,
    parameter VECTORS_PER_ROW_p = 2,
    parameter NUM_VECTORS_p = 64,
    parameter HARD_CODE_IDENTITY = 0,
    parameter HARD_CODE_ZERO = 0,
    localparam ROW_WIDTH_lp = VECTOR_WIDTH_p * VECTORS_PER_ROW_p,
    localparam ADDRESS_BIT_WIDTH_lp = $clog2(NUM_VECTORS_p * VECTORS_PER_ROW_p)
) (
    input logic clk_i,
    input logic reset,
    input logic [ADDRESS_BIT_WIDTH_lp-1:0] read_addr_i,
    input logic [ADDRESS_BIT_WIDTH_lp-1:0] write_addr_i,
    input [VECTORS_PER_ROW_p-1:0] wren_i,
    input logic [ROW_WIDTH_lp-1:0] write_data_i,
    output logic [ROW_WIDTH_lp-1:0] read_data_o
);

    // Memory array
    logic [ROW_WIDTH_lp-1:0] mem_array [NUM_VECTORS_p-1:0];

    // Read logic (Synchronous as per your comments)
    always_ff @(posedge clk_i) begin
        read_data_o <= mem_array[read_addr_i[5:0]];
    end

    // Single consolidated write process
    always_ff @(posedge clk_i) begin
        if (reset) begin
            for (int i = 0; i < NUM_VECTORS_p; i++) begin
                if (HARD_CODE_IDENTITY) begin
                    // Initialize with identity-like pattern if requested
                    case (i)
                        (NUM_VECTORS_p - 8): mem_array[i] <= 128'h00000000_00000000_00000000_00000001;
                        (NUM_VECTORS_p - 7): mem_array[i] <= 128'h00000000_00000000_00000000_00000100;
                        (NUM_VECTORS_p - 6): mem_array[i] <= 128'h00000000_00000000_00000000_00010000;
                        (NUM_VECTORS_p - 5): mem_array[i] <= 128'h00000000_00000000_00000000_01000000;
                        (NUM_VECTORS_p - 4): mem_array[i] <= 128'h00000000_00000000_00000001_00000000;
                        (NUM_VECTORS_p - 3): mem_array[i] <= 128'h00000000_00000000_00000100_00000000;
                        (NUM_VECTORS_p - 2): mem_array[i] <= 128'h00000000_00000000_00010000_00000000;
                        (NUM_VECTORS_p - 1): mem_array[i] <= 128'h00000000_00000000_01000000_00000000;
                        default:             mem_array[i] <= '0;
                    endcase
                end else begin
                    mem_array[i] <= '0;
                end
            end
        end 
        else begin
            // Write Logic
            for (int i = 0; i < VECTORS_PER_ROW_p; i++) begin
                if (wren_i[i]) begin
                    // Protection logic for Identity Matrix section
                    if ((HARD_CODE_ZERO || HARD_CODE_IDENTITY) && write_addr_i[5:3] == 3'b111) begin
                        $display("Warning: attempting to write to read-only section");
                    end 
                    else begin
                        // Perform the partitioned write
                        mem_array[write_addr_i][(i+1)*VECTOR_WIDTH_p-1 -: VECTOR_WIDTH_p] <= 
                            write_data_i[(i+1)*VECTOR_WIDTH_p-1 -: VECTOR_WIDTH_p];
                    end
                end
            end
        end
    end

endmodule