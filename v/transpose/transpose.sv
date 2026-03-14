// A pipelined transpose module for a DIM_p x DIM_p matrix with WIDTH_p bit elements
// Takes in a full row of an input matrix and outputs a full column of the transposed matrix
module transpose #( parameter DIM_p = 4, // Dimensions of the matrix (DIM_p x DIM_p) (MUST BE POWER OF 2)
                    parameter WIDTH_p = 8) // Width of data
                  ( input logic clk_i, 
                    input logic rst_n_i, // Active low reset
                    input logic col_major_i, // input is in column-major order (NONFUNCTIONAL)
                    input logic [WIDTH_p-1:0] in_data [DIM_p-1:0], // Full row input data
                    input logic valid_i, // if the input data is valid 
                    input logic ready_i, // the output module is ready to consume data
                    input logic rotate,
                    input logic transpose, 
                    ///////////////////////////////////////////////////////////////////////////////
                    output logic valid_o, // if the transposer output is valid
                    output logic ready_o, // if the transposer is ready to accept new input data
                    output logic [WIDTH_p-1:0] out_data [DIM_p-1:0] // full column output data
                  );

    // Params for row/col enable selection
    localparam DIM_CLOG2_p = $clog2(DIM_p);
    localparam logic PASS = 1'b0;
    localparam logic SHIFT = 1'b1;

    // Pre-proccess the data
    // Swap thrid and fourth rows if rotate is enabled
    logic [WIDTH_p-1:0] processed_in_data [DIM_p-1:0];
    always_comb begin 
        for (integer i = 0; i < DIM_p; i++) begin 
            if (i == 2) begin 
                processed_in_data[i] = (rotate) ? in_data[3] : in_data[2];
            end else if (i == 3) begin 
                processed_in_data[i] = (rotate) ? in_data[2] : in_data[3];
            end else begin 
                processed_in_data[i] = in_data[i];
            end
        end
    end

    // Counter values
    logic direction; // The current direction of shifting
                     // direction = 0 means horizontal (column) shift
                     // direction = 1 means vertical (row) shift
    logic [DIM_CLOG2_p-1:0] count; // bottom bits of the write counter
    logic [DIM_CLOG2_p:0] write_counter; // how many values we have written, rolls over every DIM_p writes and is used to determine the direction and count for shifting

    // 2 bit code for row/col shifting/passing. top bit is enable, bottom bit is 0 for pass, 1 for shift
    `ifdef SYNTHESIS
        // ============================================================
        // Synthesis-only version (unpacked arrays)
        // ============================================================
        logic [1:0] row_enable [DIM_p-1:0]; 
        logic [1:0] col_enable [DIM_p-1:0];
    `else
        // ============================================================
        // Simulation-only version (fully packed arrays)
        // ============================================================
        logic [DIM_p-1:0][1:0] row_enable; 
        logic [DIM_p-1:0][1:0] col_enable; 
    `endif

    // Control signals
    logic [DIM_p-1:0] valid; // which row or column is valid. Shared based on direction
    logic output_valid, enable, ready, can_read, can_write, read_or_write, transpose_r;
    /*
    output_valid: whether the output data is valid, determined by the last bit of the valid shift register
    enable: enable the rows/cols of the transposer to shift data, as well as the valid shift register
    ready: whether the transposer can accept data (its not full)
    can_read: whether data can be read out from the transposer
    can_write: whether data can be written into the transposer
    read_or_write: if we can either read or write data, used to control shifting and enabling
    */

    `ifdef SYNTHESIS
        // ============================================================
        // Synthesis-only version (unpacked arrays)
        // ============================================================
        logic [WIDTH_p-1:0] tp_bus       [DIM_p-1:0][DIM_p-1:0];
        logic [WIDTH_p-1:0] data_pass_0  [DIM_p][DIM_p];
        logic [WIDTH_p-1:0] data_pass_1  [DIM_p][DIM_p];
        logic [WIDTH_p-1:0] data_shift_0 [DIM_p][DIM_p];
        logic [WIDTH_p-1:0] data_shift_1 [DIM_p][DIM_p];
    `else
        // ============================================================
        // Simulation-only version (fully packed arrays)
        // ============================================================
        logic [DIM_p-1:0][DIM_p-1:0][WIDTH_p-1:0] tp_bus;
        logic [DIM_p-1:0][DIM_p-1:0][WIDTH_p-1:0] data_pass_0;
        logic [DIM_p-1:0][DIM_p-1:0][WIDTH_p-1:0] data_pass_1;
        logic [DIM_p-1:0][DIM_p-1:0][WIDTH_p-1:0] data_shift_0;
        logic [DIM_p-1:0][DIM_p-1:0][WIDTH_p-1:0] data_shift_1;
    `endif

    genvar row;
    genvar col;
    generate // Make the array of transposer nodes, magic interconnect logic
        for (row = 0; row < DIM_p; row++) begin : row_loop
            for (col = 0; col < DIM_p; col++) begin : col_loop // Iterate through each column first
                localparam int shift_amount_row = (col == 1) ?  1 :
                                                 (col == 2) ?  2 :
                                                 (col == 3) ? -1 : 0;

                localparam int shift_amount_col = (row == 1) ?  1 :
                                                 (row == 2) ?  2 :
                                                 (row == 3) ? -1 : 0;
                // Pass-through data stream
                //if row = 0 pass1 = in[col]
                //if col = 0 pass0 = in[row]
                //if col > 0 pass0 = bus[row][col-1]
                //if row > 0 pass1 = bus[row-1][col]

                assign data_pass_1[row][col] = (row == 0) ? (processed_in_data[col]) : tp_bus[row-1][col];
                assign data_pass_0[row][col] = (col == 0) ? (processed_in_data[row]) : tp_bus[row][col-1];

                assign data_shift_0[row][col] = (col == 0) ? 'X : tp_bus[(row + shift_amount_row + DIM_p) % DIM_p][col - 1];
                assign data_shift_1[row][col] = (row == 0) ? 'X : tp_bus[row - 1][(col + shift_amount_col + DIM_p) % DIM_p];

                //assign data_shift_0[row][col] = (col == 0) ? 'X : ((row == 0) ? tp_bus[DIM_p-1][col-1] : tp_bus[row-1][col-1]);
                //assign data_shift_1[row][col] = (row == 0) ? 'X : ((col == 0) ? tp_bus[row-1][DIM_p-1] : tp_bus[row-1][col-1]);

                // Transposer node instantiation
                tp_node #(.WIDTH_p(WIDTH_p)
                         ) node (
                          .clk_i(clk_i)
                         ,.rst_n_i(rst_n_i)
                         ,.data_pass_0_i(data_pass_0[row][col])
                         ,.data_pass_1_i(data_pass_1[row][col])
                         ,.data_shift_0_i(data_shift_0[row][col])
                         ,.data_shift_1_i(data_shift_1[row][col])
                         ,.row_en_i(row_enable[row])
                         ,.col_en_i(col_enable[col])
                         ,.data_out(tp_bus[row][col])
                         );
            end
        end
    endgenerate

    // Shift register to store what columns/rows have valid data. Single array used for both directions
    shift_reg_simple #(.WIDTH_p(1), 
                       .LENGTH_p(DIM_p))
        valid_tracker (
                       .clk_i(clk_i),
                       .rst_n_i(rst_n_i),  
                       .enable_i(enable), 
                       .shift_in_i(valid_i), 
                       .data_out_o(valid) 
                      );

    // Ready-valid handshake logic based on current state
    always_ff @(posedge clk_i) begin
        if (~rst_n_i) begin
            write_counter <= '0;
            transpose_r <= 1'b0;
            direction <= 1'b0;
        end else if (can_write) begin
            // increment if writting
            write_counter <= write_counter + 1'b1;
            transpose_r <= transpose;
            direction <= (write_counter[DIM_CLOG2_p] ~^ transpose);
        end
    end

    // Selection logic bus for whether each row/col should shift or pass based on the current count and direction.
    logic [DIM_p-1:0] selection;
    genvar j;
    generate 
        for (j = 0; j < DIM_p; j++) begin : selection_loop
            // first line always passes, then we shift more and more lines as count increases, then we go back to passing after count exceeds the index
            assign selection[j] = (j == 0 || ~rotate) ? PASS : (j <= count) ? SHIFT : PASS; 
        end
    endgenerate

    // Set the row and column enable lines
    // Has to be a generate because col and row enable are unpacked arrays.
    // 2 bit code for whether to shift or pass for this row/col, shared between row and col enables since only one is active at a time
    genvar i;
    generate
        for (i = 0; i < DIM_p; i++) begin : enable_loop
            assign col_enable[i] = (direction) ? 2'b00 : {enable, selection[i]}; // enable cols if direction is 0, otherwise enable rows
            assign row_enable[i] = (direction) ? {enable, selection[i]} : 2'b00;
        end
    endgenerate

    // If direction = 1 read last row
    // if direction = 0, read last col
    // if not transpose, read opposite of direction
    generate
        for (i = 0; i < DIM_p; i++) begin : output_loop
            assign out_data[i] = (write_counter[DIM_CLOG2_p] ~^ transpose) ? tp_bus[DIM_p-1][i] : tp_bus[i][DIM_p-1];  
        end
    endgenerate

    // Constant assignments for control signals
    assign output_valid = valid[DIM_p-1]; // The last bit of the valid shift register indicates if the output data is valid
   // direction
    assign count = write_counter[DIM_CLOG2_p-1:0];
    assign ready = output_valid ? ready_i : 1'b1;
    assign can_read = output_valid && ready_i; // able to read if output is valid and consumer is ready
    assign can_write = valid_i && ready; // able to write if input is valid and we have space
    assign enable = can_read || can_write; // enable shifting if we are either reading or writing
    assign valid_o = output_valid;
    assign ready_o = ready;

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