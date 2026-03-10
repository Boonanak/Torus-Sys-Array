// A pipelined transpose module for a DIM_p x DIM_p matrix with WIDTH_p bit elements
// Takes in a full row of an input matrix and outputs a full column of the transposed matrix
module transpose #( parameter DIM_p = 8, // Dimensions of the matrix (DIM_p x DIM_p) (MUST BE POWER OF 2)
                    parameter WIDTH_p = 8, // Width of each element in bits
                    localparam DIM_CLOG2_p = $clog2(DIM_p)
                ) (
                    input logic clk_i, 
                    input logic rst_n_i, // Active low reset
                    input logic col_major_i, // input is in column-major order (NONFUNCTIONAL)
                    input logic [WIDTH_p-1:0] in_data [DIM_p-1:0], // Full row input data
                    input logic valid_i, // if the input data is valid 
                    input logic ready_i, // the output module is ready to consume data
                    ///////////////////////////////////////////////////////////////////////////////
                    output logic valid_o, // if the transposer output is valid
                    output logic ready_o, // if the transposer is ready to accept new input data
                    output logic [WIDTH_p-1:0] out_data [DIM_p-1:0] // full column output data
                  );

    logic [DIM_CLOG2_p:0] state_counter; // Top bit is direction bit, bottom bits are the count 
    logic direction;
    logic [DIM_CLOG2_p-1:0] count;

    logic [1:0] row_enable [DIM_p-1:0]; // 2 bit code for row shifting/passing
    logic [1:0] col_enable [DIM_p-1:0]; // 2 bit code for column shifting/passing

    logic [DIM_p-1:0] valid; // which row or column is valid. Shared based on direction
    logic output_valid; // Top bit of the valid signal indicates if output is valid

    // States for ready-valid logic
    enum logic [1:0] {EMPTY, FILL, FULL, DRAIN} curr, next;
    // EMPTY: no values are in the transposer
    // FILL: We are putting values in but the output is not valid yet
    // FULL: transposer is full, output is valid. we can maintain this if we read and write at the same time
    // DRAIN: a value from the full transposer was read out before a new one could be read in, so we have to drain the whole transposer before accepting new input.

    logic [WIDTH_p-1:0] tp_bus [DIM_p-1:0][DIM_p-1:0]; // The internal buses connecting the transposer nodes, indexed by [row][col]

    genvar row;
    genvar col;
    generate // Make the array of transposer nodes, magic interconnect logic, row major input version
        for (row = 0; row < DIM_p; row++) begin : row_loop
            for (col = 0; col < DIM_p; col++) begin : col_loop // Iterate through each column first
                wire [WIDTH_p-1:0] data_pass_0, data_pass_1, data_shift_0, data_shift_1;

                // Pass-through data stream
                //if row = 0 pass1 = in[col]
                //if col = 0 pass0 = in[row]
                //if col > 0 pass0 = bus[row][col-1]
                //if row > 0 pass1 = bus[row-1][col]
                assign data_pass_1 = (row == 0) ? in_data[col] : tp_bus[row-1][col];
                assign data_pass_0 = (col == 0) ? in_data[row] : tp_bus[row][col-1];
                
                // Shift data stream
                //if col > 0 shift0 = bus[row-1][col-1] unless row == 0, then shift0 = bus[DIM_p-1][col-1]. if col == 0, dont care
                //if row > 0 shift1 = bus[row-1][col-1] unless col == 0, then shift1 = bus[row-1][DIM_p-1]. if row == 0, dont care
                assign data_shift_0 = (col == 0) ? 'X : ((row == 0) ? tp_bus[DIM_p-1][col-1] : tp_bus[row-1][col-1]);
                assign data_shift_1 = (row == 0) ? 'X : ((col == 0) ? tp_bus[row-1][DIM_p-1] : tp_bus[row-1][col-1]);

                // Transposer node instantiation
                tp_node #(.WIDTH_p(8)
                         ) node (
                          .clk_i(clk_i)
                         ,.rst_n_i(rst_n_i)
                         ,.data_pass_0_i(data_pass_0)
                         ,.data_pass_1_i(data_pass_1)
                         ,.data_shift_0_i(data_shift_0)
                         ,.data_shift_1_i(data_shift_1)
                         ,.row_en_i(row_enable[row])
                         ,.col_en_i(col_enable[col])
                         ,.data_out(tp_bus[row][col])
                         );
            end
        end
    endgenerate

    // Shift register to store what columns/rows have valid data
    shift_reg_simple #(.WIDTH_p(1), 
                       .DEPTH_p(DIM_p))
        valid_tracker (
                       .clk_i(clk_i),
                       .rst_n_i(rst_n_i),  
                       .shift_i(), 
                       .data_in_i(), 
                       .data_out_o(valid) 
                      );

    // Ready-valid handshake logic based on current state
    always_ff @(posedge clk_i) begin
        if (~rst_n_i) begin
            state_counter <= '0;
            ready_o <= 1'b1;
            valid_o <= 1'b0;
            curr <= EMPTY;
        end else begin
            curr <= next;
            if (curr == EMPTY) begin
                ready_o <= 1'b1;
                valid_o <= 1'b0;
                // hold state counter
            end else if (curr == FILL) begin
                ready_o <= 1'b1;
                valid_o <= 1'b0;
                if (valid_i) begin
                    state_counter <= state_counter + 1'b1; // Increment count if we have valid input data
                end
            end else if (curr == FULL) begin
                valid_o <= 1'b1;
                if (ready_i) begin
                    state_counter <= state_counter + 1'b1; // Increment count if we have valid input data
                    ready_o <= 1'b1; // We can accept new data if old data is being read out
                end else begin
                    ready_o <= 1'b0; // cannot accept new data until old is read out 
                end
            end else if (curr == DRAIN) begin
                ready_o <= 1'b0; // Not ready to accept new data when draining
                valid_o <= 1'b1; // Output is still valid when draining
                if (ready_i) begin
                    state_counter <= state_counter + 1'b1;
                end 
            end 
        end
    end

    // Next-state logic 
    // NOTE: Potential for glitches if valid_i glitches, we could go to the wrong state. 
    // Mostly only a problem for FULL -> DRAIN which would cause lost throughput
    always_comb begin
        case(curr)
            EMPTY: next = valid_i ? FILL : EMPTY; // If we have valid input data, start filling the pipeline
            FILL: next = (count == DIM_p-1) ? FULL : FILL; // If we've filled the pipeline, go to full, else keep filling
            FULL: next = valid_i ? FULL : DRAIN; // If we have more valid input data, stay full and keep accepting, else go to drain
            DRAIN: next = (count == 0) ? EMPTY : DRAIN; // If we've drained the pipeline, go to empty, else keep draining
        endcase
    end

    // if direction is 1, we are shifting up, 
    // so the output data is in the last row of the bus. 
    // if direction is 0, we are shifting left, so the output 
    // data is in the last column of the bus
    generate
        for (i = 0; i < DIM_p; i++) begin
            assign out_data[i] = direction ? tp_bus[DIM_p-1][i] : tp_bus[i][DIM_p-1];  
        end
    endgenerate

    // Constant assignments for control signals
    assign direction = state_counter[DIM_CLOG2_p]; // top bit of the counter is the direction bit
    assign count = state_counter[DIM_CLOG2_p-1:0]; // bottom bits of the counter are the count
    assign output_valid = valid[DIM_p-1]; // The last bit of the valid shift register indicates if the output data is valid

    // Assertions to check for valid parameter settings
    initial begin
        assert ((DIM_p & (DIM_p - 1)) == 0)
            else $fatal("DIM_p (%0d) must be a power of 2", DIM_p);
        assert (col_major_i == 1'b0)
            else $fatal("col_major_i must be 0 for row-major input, column-major input is not supported");
        assert (DIM_p > 1)
            else $fatal("DIM_p (%0d) must be greater than 1", DIM_p);
        assert (WIDTH_p > 0)
            else $fatal("WIDTH_p (%0d) must be greater than 0", WIDTH_p);
    end

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
============================================
if row = 0 pass1 = input data
if col = 0 pass0 = input data

if col > 0 shift0 = bus[col-1][row-1] unless row-1 = -1, then shift0 = bus[col-1][DIM_p-1]
if col > 0 pass0 = bus[col-1][row]

if row > 0 shift1 = bus[col-1][row-1] unless col-1 = -1, then shift1 = bus[DIM_p-1][row-1]
if row > 0 pass1 = bus[col][row-1]
*/