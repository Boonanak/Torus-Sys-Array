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

    // Params for row/col enable selection
    localparam logic PASS = 1'b0;
    localparam logic SHIFT = 1'b1;

    logic direction; // The current direction of shifting
                     // direction = 0 means horizontal (column) shift
                     // direction = 1 means vertical (row) shift
    logic [DIM_CLOG2_p-1:0] count; // bottom bits of the write counter
    logic [DIM_CLOG2_p:0] write_counter; // how many values we have written, rolls over every DIM_p writes and is used to determine the direction and count for shifting

    // 2 bit code for row/col shifting/passing. top bit is enable, bottom bit is 0 for pass, 1 for shift
    logic [1:0] row_enable [DIM_p-1:0]; 
    logic [1:0] col_enable [DIM_p-1:0]; 

    logic [DIM_p-1:0] valid; // which row or column is valid. Shared based on direction
    logic output_valid, enable, ready, can_read, can_write, read_or_write;
    /*
    output_valid: whether the output data is valid, determined by the last bit of the valid shift register
    enable: enable the rows/cols of the transposer to shift data, as well as the valid shift register
    ready: whether the transposer can accept data (its not full)
    can_read: whether data can be read out from the transposer
    can_write: whether data can be written into the transposer
    read_or_write: if we can either read or write data, used to control shifting and enabling
    */

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
                tp_node #(.WIDTH_p(WIDTH_p)
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

    // Shift register to store what columns/rows have valid data. Single array used for both directions
    shift_reg_simple #(.WIDTH_p(1), 
                       .DEPTH_p(DIM_p))
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
            ready_o <= 1'b1;
            valid_o <= 1'b0;
            enable <= 1'b0;
            write_counter <= '0;
        end else begin
            curr <= next;
            valid_o <= output_valid;
            ready_o <= ready; // if output is valid, only be ready if we are also reading, otherwise always ready
            enable <= read_or_write; 
            if (can_write) // increment if writting
                write_counter <= write_counter + 1;
        end
    end

    // Set the row and column enable lines
    // Has to be a generate because col and row enable are unpacked arrays.
    genvar i;
    generate
        for (i = 0; i < DIM_p; i++) begin : enable_loop
            wire selection = (i == 0) ? PASS : (i < count) ? SHIFT : PASS;
            assign col_enable[i] = direction ? 2'b00 : {enable, selection}; // enable cols if direction is 0, otherwise enable rows
            assign row_enable[i] = direction ? {enable, selection} : 2'b00;
        end
    endgenerate

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
    assign output_valid = valid[DIM_p-1]; // The last bit of the valid shift register indicates if the output data is valid
    assign direction = write_counter[DIM_CLOG2_p];
    assign count = write_counter[DIM_CLOG2_p-1:0];
    assign ready = output_valid ? ready_i : 1'b1;
    assign can_read = output_valid && ready_i; // able to read if output is valid and consumer is ready
    assign can_write = valid_i && ready; // able to write if input is valid and we have space
    assign read_or_write = can_read || can_write; // able to read or write at this time

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
    direction will flip every DIM_p cycles if the last row/col is valid

    row = 0 and col = 0 will always be pass


    valid_o when ever the last line is valid
    ready_o = 1 unless output_valid, then ready_o = ready_i

    if valid_i and ready_o, shift, enable. else nothing.
    if ready_i and valid_o, shift, enable, shift in invalid. else nothing. 
    if valid_i and ready_i, (provided ready_o and valid_o) shift, enable, shift in valid. else nothing
*/