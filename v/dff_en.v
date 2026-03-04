// D flip-flop with enable, parametrized bit width
module dff_en #( parameter WIDTH_p = 8 ) (
   input logic clk_i,
   input logic rst_n_i,
   input logic en_i,
   input logic [WIDTH_p-1:0] data_i,
   output logic [WIDTH_p-1:0] data_o
);

   always_ff @(posedge clk_i) begin
      if (!rst_n_i) begin
         data_o <= '0;
      end else if (en_i) begin
         data_o <= data_i;
      end
   end

endmodule