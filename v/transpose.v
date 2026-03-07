// A pipelined transpose module for a DIM_p x DIM_p matrix with WIDTH_p bit elements
// Takes in a full row of an input matrix and outputs a full column of the transposed matrix
module transpose #( parameter DIM_p = 8, // Dimensions of the matrix (DIM_p x DIM_p)
                    parameter WIDTH_p = 8, // Width of each element in bits
                    localparam DIM_CLOG2_p = $clog2(DIM_p)
                ) (
                    input logic clk_i, 
                    input logic rst_n_i, // Active low reset
                    input logic col_major_i, // input is in column-major order
                    input logic [WIDTH_p-1:0] in_data [DIM_p-1:0], // Full row input data
                    input logic valid_i, // if the input data is valid 
                    input logic ready_i, // the output module is ready to consume data
                    ///////////////////////////////////////////////////////////////////////////////
                    output logic valid_o, // if the transposer output is valid
                    output logic ready_o, // if the transposer is ready to accept new input data
                    output logic [WIDTH_p-1:0] out_data [DIM_p-1:0] // full column output data
                  );

    logic [DIM_CLOG2_p:0] state_counter; // Top bit is direction bit, bottom bits are the count 
    logic enable; // Whether to enable the nodes to shift
    logic direction;
    logic [DIM_CLOG2_p-1:0] count;
    
    // States for ready-valid logic
    enum logic state_e {EMPTY, FILL, FULL, DRAIN} curr, next;
    // EMPTY: no values are in the transposer
    // FILL: We are putting values in but the output is not valid yet
    // FULL: transposer is full, Output is valid. we can maintain this if we read and write at the same time
    // DRAIN: a value from the full transposer was read out before a new one could be read in, so we have to drain the whole transposer before accepting new input.

    genvar i;
    genvar j;
    generate // Make the array of transposer nodes, magic interconnect logic
        for (i = 0; i < DIM_p; i++) begin : row_loop
            for (j = 0; j < DIM_p; j++) begin : col_loop // Iterate through each column first
                tp_node #(.WIDTH_p(WIDTH_P)
                         ,.DIM_p(DIM_p)
                         ,.NODE_COL_p(j)
                         ,.NODE_ROW_p(i)
                         ) node (
                          .clk_i(clk_i)
                         ,.rst_n_i(rst_n_i)
                         ,.en_i(enable)
                         ,.data_pass_0_i()
                         ,.data_pass_1_i()
                         ,.data_shift_0_i()
                         ,.data_shift_1_i()
                         ,.state_counter(state_counter)
                         ,.data_out()
                         )
            end
        end
    endgenerate

    // Ready-valid handshake logic based on current state
    always_ff @(posedge clk_i) begin
        if !(rst_n_i) begin
            enable <= 1'b0;
            state_counter <= '0;
            ready_o <= 1'b1;
            valid_o <= 1'b0;
            curr <= EMPTY;
        end else begin
            curr <= next;
            if (curr == EMPTY) begin
                ready_o <= 1'b1;
                valid_o <= 1'b0;
                enable <= 1'b0;
                // hold state counter
            end else if (curr == FILL) begin
                ready_o <= 1'b1;
                valid_o <= 1'b0;
                if (valid_i) begin
                    state_counter <= state_counter + 1; // Increment count if we have valid input data
                    enable <= 1'b1; // Enable the nodes to shift in the data
                end else begin
                    enable <= 1'b0; // Hold the data in place if we don't have valid input data
                end
            end else if (curr == FULL) begin
                valid_o <= 1'b1;
                if (ready_i) begin
                    state_counter <= state_counter + 1; // Increment count if we have valid input data
                    enable <= 1'b1; 
                    ready_o <= 1'b1; // We can accept new data if old data is being read out
                end else begin
                    enable <= 1'b0;
                    ready_o <= 1'b0; // cannot accept new data until old is read out 
                end
            end else if (curr == DRAIN) begin
                ready_o <= 1'b0; // Not ready to accept new data when draining
                valid_o <= 1'b1; // Output is still valid when draining
                if (ready_i) begin
                    state_counter <= state_counter + 1; 
                    enable <= 1'b1; // Enable the nodes to shift out the data
                end else begin
                    enable <= 1'b0; // Hold the data in place
                end
            end 
        end
    end

    // Next-state logic 
    always_comb begin
        case(curr)
            EMPTY: next = valid_i ? FILL : EMPTY; // If we have valid input data, start filling the pipeline
            FILL: next = (count == DIM_p-1) ? FULL : FILL; // If we've filled the pipeline, go to full, else keep filling
            FULL: next = valid_i ? FULL : DRAIN; // If we have more valid input data, stay full and keep accepting, else go to drain
            DRAIN: next = (count == 0) ? EMPTY : DRAIN; // If we've drained the pipeline, go to empty, else keep draining
        endcase
    end

    // Easier break-out of state counter bits
    assign direction = state_counter[DIM_CLOG2_p]; // top bit of the counter is the direction bit
    assign count = state_counter[DIM_CLOG2_p-1:0]; // bottom bits of the counter are the count

endmodule


/*
If the transposer it empty, output ready_o and ~valid_o, and wait for valid_i
on valid_i, enable the array, and shift in the data.
If valid_i remains true, keep shifting, else wait for valid_i. Maintain ready_o

once data reaches the end of the pipeline, set valid_o and freeze the pipeline
if ready_i is set, advance the pipeline until it goes false
if there is valid data to put into the pipeline that can immediatly follow the previous, keep accpeting new data
if not, set ~ready_o and wait to empty the pipeline
once empty, reset, ready_o

*/