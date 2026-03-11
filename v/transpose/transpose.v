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

    logic direction;
    logic [DIM_CLOG2_p-1:0] count;
    logic [DIM_CLOG2_p:0] write_counter;

    logic [1:0] row_enable [DIM_p-1:0]; // 2 bit code for row shifting/passing
    logic [1:0] col_enable [DIM_p-1:0]; // 2 bit code for column shifting/passing

    logic [DIM_p-1:0] valid; // which row or column is valid. Shared based on direction
    logic output_valid; // Top bit of the valid signal indicates if output is valid, all valid is if every bit is valid
    logic shift, enable;

    // States for ready-valid logic
    enum logic [1:0] {EMPTY, PARTIAL, FULL} curr, next;
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
                       .enable_i(shift), 
                       .shift_in_i(valid_i), 
                       .data_out_o(valid) 
                      );

    // Ready-valid handshake logic based on current state
    always_ff @(posedge clk_i) begin
        if (~rst_n_i) begin
            ready_o <= 1'b1;
            valid_o <= 1'b0;
            shift <= 1'b0;
            curr <= EMPTY;
            enable <= 1'b0;
            write_counter <= '0;
        end else begin
            curr <= next;
            valid_o <= output_valid;
            if (curr == EMPTY) begin
                ready_o <= 1'b1;
                valid_o <= 1'b0;
                shift <= 1'b0;
                enable <= 1'b0;
            end else if (curr == PARTIAL) begin
                
            end else if (curr == FULL) begin
                
            end     
        end
    end

    // Next-state logic 
    always_comb begin
        case(curr)
            EMPTY: next = valid_i ? PARTIAL : EMPTY;
            PARTIAL: next = (valid == 0) EMPTY : (valid == (DIM_p-1)) ? FULL : PARTIAL;
            FULL: next = (valid == (DIM_p-1)) ? FULL : PARTIAL;
        endcase
    end

    // Set the row and column enable lines
    generate
        logic selection;
        for (int i = 0; i < DIM_p; i++) begin : enable_loop
            if (i == 0) 
                assign selection = 1'b0; // pass
            else if (i < count)
                assign selection = 1'b1; // shift
            else
                assign selection = 1'b0; // pass
            assign col_enable[i] = direction ? '0 : {enable, selection};
            assign row_enable[i] = direction ? {enable, selection} : '0;
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

*/