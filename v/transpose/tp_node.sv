// This module is a single node meant for use in the transposer
// Has 4 input data streams, and will chose one to be the output 
// Output selection takes into account the parameterized position and the 
// current value of the counter, which is used to control the behavior of the node
module tp_node #(parameter WIDTH_p = 8, // bitwidth of the stored data
                parameter DIM_p = 8, // dimension of the transposer (ONLY SUPPORTS powers of 2)
                parameter NODE_COL_p = 0, // this nodes column index in the transposer
                parameter NODE_ROW_p = 0  // this nodes row index in the transposer
                                          // bottom right is (0,0) top left is (DIM_p-1, DIM_p-1)
             ) (
                input logic clk_i,
                input logic rst_n_i,
                input logic en_i,
                input logic [WIDTH_p-1:0] data_pass_0_i, // data passed in from the mode 0 direction
                input logic [WIDTH_p-1:0] data_pass_1_i, // data passed in from the mode 1 direction
                input logic [WIDTH_p-1:0] data_shift_0_i, // data shifted in from mode 0 direction
                input logic [WIDTH_p-1:0] data_shift_1_i, // data shifted in from mode 1 direction
                input logic [$clog2(DIM_p)+1:0] state_counter, // external state counter to control the node's behavior
                                                               // top bit is the direction bit, bottom bits are the count within the current direction
                output logic [WIDTH_p-1:0] data_out
               );

    logic direction; // which direction the transposer is operating in
                     // Direction 0: Data flows in from right and read out from left
                     // Direction 1: Data flows in from bottom and read out from top
    logic [$clog2(DIM_p)-1:0] count; // which stage of the current direction we are in
                                     // count 0 = transposer has an entire single matrix in it
                                     // count 1-7 part of two matrices are in the transposer

    // Output data on the clock edge based on the current state and node position
    always_ff @(posedge clk_i) begin
        if (!rst_n_i) begin
            data_out <= '0; 
        end else if (en_i) begin
            if (direction == 0) begin
                // direction 0 operation
                if (NODE_COL_p == 0) begin
                    data_out <= data_pass_0_i; // right edge just passes data through
                end else if (NODE_COL_p <= count) begin
                    data_out <= data_shift_0_i; // shift in from the right
                end else begin
                    data_out <= data_pass_0_i; // pass through from the right
                end
            end else begin
                // direction 1 operation
                if (NODE_ROW_p == 0) begin
                    data_out <= data_pass_1_i; // bottom edge just passes data through
                end else if (NODE_ROW_p <= count) begin
                    data_out <= data_shift_1_i; // shift in from the bottom
                end else begin
                    data_out <= data_pass_1_i; // pass through from the bottom
                end
            end
        end
        // else hold the current value
    end

    // Decode the direction and count from the state counter
    assign direction = state_counter[$clog2(DIM_p)]; // top bit of the counter is the direction bit
    assign count = state_counter[$clog2(DIM_p)-1:0]; // bottom bits of the counter are the count

endmodule

/* WIP workspace for sorting out the mux logic
if col <= count and direction = 0, and col != 0
shift0, else pass0

if row <= count and direction = 1, and row != 0
shift1, else pass1

// edge nodes
if direction = 0 and col = 0, pass0 
if direction = 1 and row = 0, pass1
*/