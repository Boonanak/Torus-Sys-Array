import PE_pkg::*;

module Top_level #(
    parameter int ring_width_p = 32,
    parameter int out_width_p = 64,
    parameter int id_p         = 0,
    parameter int DIM_p        = 4,
    parameter int WIDTH_p      = 8
)(
    input  logic                    clk_i,
    input  logic                    reset_i,

    input  logic                    v_i,
    input  logic [ring_width_p-1:0] data_i,
    output logic                    ready_o,
    input  logic                    in_major_mode,
    input  logic                    in_load_weight,

    output logic                    v_o,
    output logic [out_width_p-1:0] data_o,
    input  logic                    ready_i
);

    // ----------------------------------------------------------------
    // Decoded current input packet fields
    // Packet format assumed:
    // [7:0]    row element 0
    // [15:8]   row element 1
    // [23:16]  row element 2
    // [31:24]  row element 3
    //          major_mode: 1=row-major, 0=column-major
    //          load_weight: 1=weights, 0=data
    // remaining bits unused here
    // ----------------------------------------------------------------
    logic [WIDTH_p-1:0] in_row_data [DIM_p-1:0];

    assign in_row_data[0] = data_i[7:0];
    assign in_row_data[1] = data_i[15:8];
    assign in_row_data[2] = data_i[23:16];
    assign in_row_data[3] = data_i[31:24];

    // ----------------------------------------------------------------
    // Input handshake
    // Accept a row whenever the pipeline can take it
    // ----------------------------------------------------------------
    logic input_fire;

    // ----------------------------------------------------------------
    // Transpose interface
    // ----------------------------------------------------------------
    logic signed [WIDTH_p-1:0] transpose_in_data [DIM_p-1:0];
    logic               transpose_valid_i;
    logic               transpose_ready_o;
    logic               transpose_valid_o;
    logic               transpose_col_major;
    logic               transpose_rotate;
    logic               transpose_do_transpose;
    logic signed [WIDTH_p-1:0] transpose_out_data [DIM_p-1:0];

    // ----------------------------------------------------------------
    // Systolic array interface
    // ----------------------------------------------------------------
    logic               sys_row_major;
    logic               sys_load_B;
    logic               sys_output_valid;
    logic               sys_output_ready;
    logic               sys_transposer_ready;

    logic signed [15:0]        A_out_right  [DIM_p-1:0];
    logic signed [15:0]        PS_out_right [DIM_p-1:0];

    // ----------------------------------------------------------------
    // Output holding register
    // One completed result packet can be buffered here
    // ----------------------------------------------------------------
    logic [out_width_p-1:0] out_pkt_r, out_pkt_n;
    logic                    out_valid_r, out_valid_n;

    
    // ----------------------------------------------------------------
    // Control mapping
    // ----------------------------------------------------------------
    assign transpose_col_major    = 1'b0;   // temporary forces input

    // Stream rows directly in when accepted
    assign transpose_valid_i = v_i & ready_o;
    assign input_fire        = v_i & ready_o;

    //assign transpose_rotate = ctrl_front.rotate;   // no rotate on write
    //assign transpose_do_transpose = ctrl_front.do_transpose;   // no transpose on read


    // ----------------------------------------------------------------
    // Control FIFO to keep control bits aligned with rows through
    // variable-latency transpose
    // ----------------------------------------------------------------
    typedef struct packed {
        logic major_mode;
        logic load_weight;
        logic rotate;
        logic do_transpose;
    } ctrl_t;

    localparam int CTRL_FIFO_DEPTH = 8;
    localparam int CTRL_FIFO_PTR_W = $clog2(CTRL_FIFO_DEPTH);

    ctrl_t ctrl_fifo [CTRL_FIFO_DEPTH-1:0];

    logic [CTRL_FIFO_PTR_W-1:0] ctrl_wr_ptr_r, ctrl_wr_ptr_n;
    logic [CTRL_FIFO_PTR_W-1:0] ctrl_rd_ptr_r, ctrl_rd_ptr_n;
    logic [CTRL_FIFO_PTR_W  :0] ctrl_count_r,  ctrl_count_n;

    logic ctrl_fifo_full, ctrl_fifo_empty;
    logic ctrl_enq, ctrl_deq;

    ctrl_t ctrl_front;

    assign ctrl_fifo_empty = (ctrl_count_r == 0);
    assign ctrl_fifo_full  = (ctrl_count_r == CTRL_FIFO_DEPTH);

    // Enqueue control bits when an input row is accepted
    assign ctrl_enq = input_fire;

    // Dequeue control bits when transpose output is accepted by systolic
    assign ctrl_deq = transpose_valid_o & sys_transposer_ready & ~ctrl_fifo_empty;

    // Front entry corresponds to current transpose output transaction
    assign ctrl_front = ctrl_fifo[ctrl_rd_ptr_r];

    //assign sys_row_major = ctrl_front.major_mode;
    assign transpose_do_transpose    = ctrl_front.load_weight;

    assign sys_row_major = (!ctrl_fifo_empty) ? ctrl_front.major_mode  : 1'b0;
    assign sys_load_B    = (!ctrl_fifo_empty) ? ctrl_front.load_weight : 1'b0;
    

    always_comb begin
        ctrl_wr_ptr_n = ctrl_wr_ptr_r;
        ctrl_rd_ptr_n = ctrl_rd_ptr_r;
        ctrl_count_n  = ctrl_count_r;

        case ({ctrl_enq, ctrl_deq})
            2'b10: begin
                // enqueue only
                ctrl_wr_ptr_n = ctrl_wr_ptr_r + 1'b1;
                ctrl_count_n  = ctrl_count_r + 1'b1;
            end

            2'b01: begin
                // dequeue only
                ctrl_rd_ptr_n = ctrl_rd_ptr_r + 1'b1;
                ctrl_count_n  = ctrl_count_r - 1'b1;
            end

            2'b11: begin
                // simultaneous enqueue and dequeue
                ctrl_wr_ptr_n = ctrl_wr_ptr_r + 1'b1;
                ctrl_rd_ptr_n = ctrl_rd_ptr_r + 1'b1;
            end

            default: begin
            end
        endcase
    end


    // ----------------------------------------------------------------
    // Cycle counters for rotate / do_transpose timing
    // ----------------------------------------------------------------
    localparam int CNT_W = $clog2(DIM_p + 1);  // 3 bits for DIM_p=4

    logic [CNT_W-1:0] in_cycle_cnt_r,  in_cycle_cnt_n;   // counts accepted input rows
    logic [CNT_W-1:0] out_cycle_cnt_r, out_cycle_cnt_n;  // counts consumed output rows

    logic rotate_armed_r,       rotate_armed_n;
    logic do_transpose_armed_r, do_transpose_armed_n;

    always_comb begin
        in_cycle_cnt_n       = in_cycle_cnt_r;
        out_cycle_cnt_n      = out_cycle_cnt_r;
        rotate_armed_n       = rotate_armed_r;
        do_transpose_armed_n = do_transpose_armed_r;

        // Count input fires; arm rotate after DIM_p inputs received
        if (input_fire) begin
            if (in_cycle_cnt_r == CNT_W'(DIM_p)) begin
                in_cycle_cnt_n = '0;
                rotate_armed_n = 1'b1;          // assert rotate on the NEXT input
            end else begin
                in_cycle_cnt_n = in_cycle_cnt_r + 1'b1;
            end
        end

        // Clear rotate once it has been consumed by the transposer
        if (rotate_armed_r && ctrl_deq)
            rotate_armed_n = 1'b0;

        // Count output fires (transpose→systolic handshakes);
        // arm do_transpose after DIM_p outputs consumed
        if (ctrl_deq) begin
            if (out_cycle_cnt_r == CNT_W'(DIM_p)) begin
                out_cycle_cnt_n      = '0;
                do_transpose_armed_n = 1'b1;    // assert do_transpose on the NEXT output
            end else begin
                out_cycle_cnt_n = out_cycle_cnt_r + 1'b1;
            end
        end

        // Clear do_transpose once consumed
        if (do_transpose_armed_r && ctrl_deq)
            do_transpose_armed_n = 1'b0;
    end

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            in_cycle_cnt_r       <= '0;
            out_cycle_cnt_r      <= '0;
            rotate_armed_r       <= 1'b0;
            do_transpose_armed_r <= 1'b0;
        end else begin
            in_cycle_cnt_r       <= in_cycle_cnt_n;
            out_cycle_cnt_r      <= out_cycle_cnt_n;
            rotate_armed_r       <= rotate_armed_n;
            do_transpose_armed_r <= do_transpose_armed_n;
        end
    end

    // Replace the ctrl_fifo-based assignments with the armed flags:
    assign transpose_rotate       = in_load_weight;
    //assign transpose_do_transpose = do_transpose_armed_r;



    generate
        genvar i;
        for (i = 0; i < DIM_p; i++) begin : g_tp_in
            assign transpose_in_data[i] = in_row_data[i];
        end
    endgenerate


    // Backpressure input if:
    // - node disabled
    // - transpose cannot accept
    // - systolic cannot accept transpose output path
    // - output register already full and we don't want unchecked overflow
    
    assign ready_o = transpose_ready_o;
                //    & sys_transposer_ready
                //    & (~out_valid_r | ready_i)
                //    & (~ctrl_fifo_full);

    // Output interface to ring
    assign v_o    = out_valid_r;
    assign data_o = out_pkt_r;


    always_ff @(posedge clk_i) begin
        if (transpose_valid_o && sys_transposer_ready) begin
            $display("TOP transpose out @ %0t : rotate=%0b trans=%0b data=[%0d %0d %0d %0d]",
                    $time,
                    ctrl_front.rotate,
                    ctrl_front.do_transpose,
                    transpose_out_data[0],
                    transpose_out_data[1],
                    transpose_out_data[2],
                    transpose_out_data[3]);
        end
    end

    // Systolic can present a completed result when output holding reg is free,
    // or when the current packet is being consumed this cycle.
    assign sys_output_ready = sys_output_valid
                        & ((~out_valid_r) | (out_valid_r & ready_i));

    // ----------------------------------------------------------------
    // Output packet formatting / hold logic
    // ----------------------------------------------------------------
    always_comb begin
        out_pkt_n   = out_pkt_r;
        out_valid_n = out_valid_r;

        if (out_valid_r && ready_i) begin
            out_valid_n = 1'b0;
            out_pkt_n   = '0;
        end

        if (sys_output_valid && sys_output_ready) begin
            out_pkt_n = '0;
            
            // full 16-bit PS results into [63:0]
            out_pkt_n[15:0]   = PS_out_right[0];
            out_pkt_n[31:16]  = PS_out_right[1];
            out_pkt_n[47:32]  = PS_out_right[2];
            out_pkt_n[63:48]  = PS_out_right[3];

            out_valid_n       = 1'b1;
        end
    end

    // ----------------------------------------------------------------
    // Sequential logic
    // ----------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            out_pkt_r      <= '0;
            out_valid_r    <= 1'b0;

            ctrl_wr_ptr_r  <= '0;
            ctrl_rd_ptr_r  <= '0;
            ctrl_count_r   <= '0;

        end
        else begin
            out_pkt_r   <= out_pkt_n;
            out_valid_r <= out_valid_n;

            // Write new control entry on accepted input row
            if (ctrl_enq) begin
                ctrl_fifo[ctrl_wr_ptr_r].major_mode  <= in_major_mode;
                ctrl_fifo[ctrl_wr_ptr_r].load_weight <= in_load_weight;
                ctrl_fifo[ctrl_wr_ptr_r].do_transpose <= ~in_load_weight;
                ctrl_fifo[ctrl_wr_ptr_r].rotate       <= in_load_weight;
            end

            ctrl_wr_ptr_r <= ctrl_wr_ptr_n;
            ctrl_rd_ptr_r <= ctrl_rd_ptr_n;
            ctrl_count_r  <= ctrl_count_n;

        end
    end
    logic systransreadyfix;

    // logic for counter to control trans
    logic transpose_handshake_suceeded, sys_array_handshake_suceeded;
    logic transpose_matrix_1, transpose_matrix_2;
    logic [1:0] write_counter;

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            transpose_matrix_1 <= 1'b0;
            transpose_matrix_2 <= 1'b0;
            write_counter <= '0;
        end else begin
            if (write_counter == 2'b00 && v_i)
                transpose_matrix_2 <= in_load_weight; // Store the new transpose signal removed~
            if (transpose_handshake_suceeded)
                write_counter <= write_counter + 1'b1;
            if (sys_array_handshake_suceeded && write_counter == 2'b00)
                transpose_matrix_1 <= transpose_matrix_2; // update top matrix with stored tranpose signal
        end 
    end 

    //assign transpose_do_transpose = transpose_matrix_1; // replace transpose_do_transpose with this signal transpose (feel free to rename)
    assign transpose_handshake_suceeded = transpose_valid_i && transpose_ready_o;
    assign sys_array_handshake_suceeded = transpose_valid_o && sys_transposer_ready;    

    // ----------------------------------------------------------------
    // Transposer
    // NOTE: assertion in transpose that forces col_major_i=0
    // ----------------------------------------------------------------
    transpose #(
        .DIM_p   (DIM_p),
        .WIDTH_p (WIDTH_p)
    ) u_transpose (
        .clk_i       (clk_i),
        .rst_n_i     (~reset_i),
        .col_major_i (transpose_col_major),
        .in_data     (transpose_in_data),
        .valid_i     (transpose_valid_i),
        .ready_i     (sys_transposer_ready),
        .rotate      (transpose_rotate),
        .transpose   (transpose_do_transpose),
        .valid_o     (transpose_valid_o),
        .ready_o     (transpose_ready_o),
        .out_data    (transpose_out_data)
    );

    // ----------------------------------------------------------------
    // Systolic array
    // ----------------------------------------------------------------
    sys_array #(
        .ROWS (DIM_p),
        .COLS (DIM_p)
    ) u_sys_array (
        .clk_i                   (clk_i),
        .reset                   (reset_i),
        .load_B                  (sys_load_B),
        .row_major               (1'b1), // sys_row_major
        .transposer_data         (transpose_out_data),
        .A_out_right             (A_out_right),
        .PS_out_right            (PS_out_right),
        .transposer_valid_in     (transpose_valid_o),
        .transposer_ready_out    (sys_transposer_ready),
        .output_buffer_ready_in  (sys_output_ready),
        .output_buffer_valid_out (sys_output_valid)
    );

endmodule