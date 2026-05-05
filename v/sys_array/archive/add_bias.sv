module add_bias #(
     parameter data_width_p = 16
    ,parameter matrix_dim_p = 8
)
(
     input  logic   clk_i
    ,input  logic   reset
    ,input  logic   enable
    ,input  logic   [data_width_p - 1 : 0] bias         [matrix_dim_p - 1 : 0]
    ,input  logic   [data_width_p - 1 : 0] partial_sum  [matrix_dim_p - 1 : 0]

    ,output logic   [data_width_p - 1 : 0] out          [matrix_dim_p - 1 : 0]
);

    always_ff @(posedge clk_i) begin 
        if (reset) begin 
            out <= '0;
        end
        else begin 
            out <= (enable) ? ($signed(bias) + $signed(partial_sum)) : out;
        end
    end

endmodule