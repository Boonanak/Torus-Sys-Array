// A pipelined transpose module for a DIM_p x DIM_p matrix with WIDTH_p bit elements
// Takes in a full row of an input matrix and outputs a full column of the transposed matrix
module transpose #( parameter DIM_p = 4, // Dimensions of the matrix (DIM_p x DIM_p) (MUST BE POWER OF 2)
                    parameter WIDTH_p = 8) // Width of data
                  ( input logic clk_i, 
                    input logic rst_n_i, // Active low reset
                    input logic [WIDTH_p-1:0] in_data [DIM_p-1:0], // Full row input data
                    input logic valid_i, // if the input data is valid 
                    input logic ready_i, // the output module is ready to consume data
                    input logic transpose, // to transpose or not transpose, assert on read
                    ///////////////////////////////////////////////////////////////////////////////
                    output logic valid_o, // if the transposer output is valid
                    output logic ready_o, // if the transposer is ready to accept new input data
                    output logic [WIDTH_p-1:0] out_data [DIM_p-1:0] // full column output data
                  );

    // Params for row/col enable selection
    localparam DIM_CLOG2_p = $clog2(DIM_p);

    // Counter values
    logic direction; // The current direction of shifting
                     // direction = 0 means horizontal (column) shift
                     // direction = 1 means vertical (row) shift
    logic [DIM_CLOG2_p-1:0] count; // bottom bits of the write counter
    logic [DIM_CLOG2_p:0] write_counter; // how many values we have written, rolls over every DIM_p writes and is used to determine the direction and count for shifting

    // 2 bit code for row/col shifting/passing. top bit is enable, bottom bit is 0 for pass, 1 for shift
    logic [DIM_p-1:0] row_enable; 
    logic [DIM_p-1:0] col_enable; 

    // Control signals
    logic [DIM_p-1:0] valid; // which row or column is valid. Shared based on direction
    logic output_valid, enable, can_read, ready, can_write, override_direction;
    /*
    output_valid: whether the output data is valid, determined by the last bit of the valid shift register
    enable: enable the rows/cols of the transposer to shift data, as well as the valid shift register
    can_read: whether data can be read out from the transposer
    ready: whether or not we can write data
    can_write: whether data can be written into the transposer
    override_direction: if transposing is disabled, store the current direction and override andy direction changes to this
    */

    `ifdef SYNTHESIS
        // ============================================================
        // Synthesis-only version (unpacked arrays)
        // ============================================================
        logic [WIDTH_p-1:0] tp_bus       [DIM_p-1:0][DIM_p-1:0];
        logic [WIDTH_p-1:0] data_pass_0  [DIM_p][DIM_p];
        logic [WIDTH_p-1:0] data_pass_1  [DIM_p][DIM_p];
    `else
        // ============================================================
        // Simulation-only version (fully packed arrays)
        // ============================================================
        logic [DIM_p-1:0][DIM_p-1:0][WIDTH_p-1:0] tp_bus;
        logic [DIM_p-1:0][DIM_p-1:0][WIDTH_p-1:0] data_pass_0;
        logic [DIM_p-1:0][DIM_p-1:0][WIDTH_p-1:0] data_pass_1;
    `endif

    genvar row;
    genvar col;
    generate // Make the array of transposer nodes, magic interconnect logic
        for (row = 0; row < DIM_p; row++) begin : row_loop
            for (col = 0; col < DIM_p; col++) begin : col_loop // Iterate through each column first
                // Pass-through data stream
                //if row = 0 pass1 = in[col]
                //if col = 0 pass0 = in[row]
                //if col > 0 pass0 = bus[row][col-1]
                //if row > 0 pass1 = bus[row-1][col]

                assign data_pass_1[row][col] = (row == 0) ? (in_data[col]) : tp_bus[row-1][col];
                assign data_pass_0[row][col] = (col == 0) ? (in_data[row]) : tp_bus[row][col-1];

                // Transposer node instantiation
                tp_node #(.WIDTH_p(WIDTH_p)
                         ) node (
                          .clk_i(clk_i)
                         ,.rst_n_i(rst_n_i)
                         ,.data_pass_0_i(data_pass_0[row][col])
                         ,.data_pass_1_i(data_pass_1[row][col])
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
            override_direction <= 1'b0;
        end else begin
            override_direction <= direction;
            if (can_write) // increment if writting
                write_counter <= write_counter + 1'b1;
        end
    end

    // Set the row and column enable lines, either all rows are enabled or all columns
    assign col_enable = direction ? '0 : {DIM_p{enable}};
    assign row_enable = direction ? {DIM_p{enable}} : '0;

    // If direction = 1 read last row
    // if direction = 0, read last col
    // if not transpose, don't change direction
    genvar i;
    generate
        for (i = 0; i < DIM_p; i++) begin : output_loop
            assign out_data[i] = (direction) ? tp_bus[DIM_p-1][i] : tp_bus[i][DIM_p-1];  
        end
    endgenerate

    // Constant assignments for control signals
    assign output_valid = valid[DIM_p-1]; // The last bit of the valid shift register indicates if the output data is valid
    assign direction = transpose ? (write_counter[DIM_CLOG2_p]) : override_direction;
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
        assert (DIM_p > 1)
            else $fatal("DIM_p (%0d) must be greater than 1", DIM_p);
        assert (WIDTH_p > 0)
            else $fatal("WIDTH_p (%0d) must be greater than 0", WIDTH_p);
    end

endmodule