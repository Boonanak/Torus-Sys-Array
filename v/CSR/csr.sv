// Control State Register (CSR) for storing control, status, and error information
// Has 4 write modes:
// 00: Read mode - does not write anything to CSR
// 01: Set mode - if a bit is 1 in data_i, set it to 1 in the csr, else keep it the same
// 10: Clear mode - if a bit is 1 in data_i, set it to 0 in the csr, else keep it the same
// 11: Assign mode - directly assigns the CSR register to data_i
// data_o is sychrnonous and not write-through (reads out the old value not the new value).
module csr #(   parameter WIDTH_p = 64,
                parameter [WIDTH_p-1:0] RESET_VALUE_p = '0 // Default reset value for the CSR register
            ) (
                input logic clk_i,
                input logic rst_n_i,
                input logic [WIDTH_p-1:0] data_i,
                input logic [1:0] write_mode_i,
                output logic [WIDTH_p-1:0] data_o
            );

    logic [WIDTH_p-1:0] csr_reg;

    always_ff @(posedge clk_i) begin
        if (!rst_n_i) begin
            csr_reg <= RESET_VALUE_p; // Reset the CSR register to the specified reset value
        end else begin
            case (write_mode_i)
                2'b01: csr_reg <= csr_reg | data_i;     // Set mode: set bits in csr_reg according to data_i
                2'b10: csr_reg <= csr_reg & ~data_i;    // Clear mode: clear bits in csr_reg according to data_i
                2'b11: csr_reg <= data_i;               // Assign mode: directly assign the csr_reg to data_i
                default: csr_reg <= csr_reg;            // No change to csr_reg
            endcase
            data_o <= csr_reg; // Output the current value of the CSR register synchronously (not write-through)
        end
    end

endmodule