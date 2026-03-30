// Serial in parallel out shift register
// Parametrized depth and bit width
// Supports write and read operations with full and empty flags
module shift_reg #(  parameter WIDTH_p = 8,
                     parameter DEPTH_p = 8
                ) (
                     input logic clk_i,
                     input logic rst_n_i,
                     input logic write_i,
                     input logic read_i,
                     input logic [WIDTH_p-1:0] data_i,
                     output logic [WIDTH_p-1:0] [DEPTH_p-1:0] data_o,
                     output logic full_o,
                     output logic empty_o
                  ); 

   logic [$clog2(DEPTH_p) + 1:0] write_cnt; // Store how many elements have been written since last read
   logic full, empty, can_write;
   logic [WIDTH_p-1:0] [DEPTH_p-1:0] shift_reg; // Shift register bus

   genvar i;
   generate
      // Set up each dff to send its content to the next dff
      for (i = 0; i < DEPTH_p; i++) begin : shift_reg_gen
         dff_en #(.WIDTH_p(WIDTH_p)) dff (
            .clk_i(clk_i),
            .rst_n_i(rst_n_i),
            .en_i(can_write), // Shift on write
            .data_i(i == 0 ? data_i : shift_reg[i-1]), // Input is either the new data or the previous stage's output
            .data_o(shift_reg[i]) // Output goes to the shift register bus
         );
      end
   endgenerate

   // Write pointer logic
   always_ff @(posedge clk_i) begin
      if (!rst_n_i)
         write_cnt <= 0;
      else if (can_write)
         write_cnt <= write_cnt + 1; // Increment write counter on write
      else if (read_i)
         write_cnt <= 0; // Reset write counter on read
      full_o <= full; // Update full output
      empty_o <= empty; // Update empty output
   end

   // Full and empty flag logic
   always_comb begin
      full = (write_cnt == DEPTH_p); // Full when write counter reaches DEPTH_p (bitwidth set to fit decimal DEPTH_p)
      empty = (write_cnt == 0); // Empty when write counter is at 0
      data_o = shift_reg; // Output the current state of the shift register (combinational so we don't create more dffs)
      can_write = write_i && !full; // when writes are valid
   end

endmodule