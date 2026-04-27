module lardi_client #(
    parameter WIDTH_p = 16, // INVALID for width <= 1
    parameter logic DIRECTION_p = 0 // 0 for shift out left, 1 for shift out right
) (
    input logic lardi_clk_i,
    input logic reset_n_i,
    input logic lardi_capture,
    input logic [WIDTH_p-1:0] lardi_src_i,
    output logic lardi_client_data_o
);

    logic [WIDTH_p-1:0] shift_reg;

    // On reset, clear the shift register
    // On capture, load shift reg in parallel with the client data
    // On neither, shift data out once per cycle, shifting in 0s on the right
    always_ff @(posedge lardi_clk_i or negedge reset_n_i) begin
        if (!reset_n_i) begin
            shift_reg <= '0;
        end else if (lardi_capture) begin
            shift_reg <= lardi_src_i;
        end else begin
            shift_reg <= DIRECTION_p ? {1'b0, shift_reg[WIDTH_p-1:1]} : {shift_reg[WIDTH_p-2:0], 1'b0};
        end
    end

    // assign to the top bit of the shift register as the output, 
    // this is the current client data bit being shifted out
    assign lardi_client_data_o = DIRECTION_p ? shift_reg[0] : shift_reg[WIDTH_p-1];

    // Ensure only valid conditions are set for the parameters
    initial begin
        assert(WIDTH_p > 1) else $error("WIDTH_p must be greater than 1 for lardi_client");
    end
    
endmodule