import PE_pkg::*;

module Top_level #(
    parameter int ring_width_p = 75,
    parameter int id_p         = 0,
    parameter int DIM_p        = 4,
    parameter int WIDTH_p      = 8
)(
    input  logic                    clk_i,
    input  logic                    reset_i,
    input  logic                    en_i,

    input  logic                    v_i,
    input  logic [ring_width_p-1:0] data_i,
    output logic                    ready_o,

    output logic                    v_o,
    output logic [ring_width_p-1:0] data_o,
    input  logic                    yumi_i
);

    initial begin
        assert (ring_width_p == 75)
            else $fatal("toplevel currently expects ring_width_p = 75");
        assert (DIM_p == 4)
            else $fatal("toplevel currently expects DIM_p = 4");
        assert (WIDTH_p == 8)
            else $fatal("toplevel currently expects WIDTH_p = 8");
    end

    // ----------------------------------------------------------------
    // Decoded current input packet fields
    // Packet format assumed:
    // [7:0]    row element 0
    // [15:8]   row element 1
    // [23:16]  row element 2
    // [31:24]  row element 3
    // [32]     major_mode: 1=row-major, 0=column-major
    // [33]     load_weight: 1=weights, 0=data
    // remaining bits unused here
    // ----------------------------------------------------------------
    logic [WIDTH_p-1:0] in_row_data [DIM_p-1:0];
    logic               in_major_mode;
    logic               in_load_weight;

    assign in_row_data[0] = data_i[7:0];
    assign in_row_data[1] = data_i[15:8];
    assign in_row_data[2] = data_i[23:16];
    assign in_row_data[3] = data_i[31:24];
    assign in_major_mode  = data_i[32];
    assign in_load_weight = data_i[33];

    // ----------------------------------------------------------------
    // Input handshake
    // Accept a row whenever the pipeline can take it
    // ----------------------------------------------------------------
    logic input_fire;

    // ----------------------------------------------------------------
    // Transpose interface
    // ----------------------------------------------------------------
    logic [WIDTH_p-1:0] transpose_in_data [DIM_p-1:0];
    logic               transpose_valid_i;
    logic               transpose_ready_o;
    logic               transpose_valid_o;
    logic               transpose_col_major;
    logic [WIDTH_p-1:0] transpose_out_data [DIM_p-1:0];

    // ----------------------------------------------------------------
    // Systolic array interface
    // ----------------------------------------------------------------
    logic               sys_row_major;
    logic               sys_load_B;
    logic               sys_output_valid;
    logic               sys_output_ready;
    logic               sys_transposer_ready;

    logic [15:0]        A_out_right  [DIM_p-1:0];
    logic [15:0]        PS_out_right [DIM_p-1:0];

    // ----------------------------------------------------------------
    // Output holding register
    // One completed result packet can be buffered here
    // ----------------------------------------------------------------
    logic [ring_width_p-1:0] out_pkt_r, out_pkt_n;
    logic                    out_valid_r, out_valid_n;

    // Control registers to allow controls to persist
    logic major_mode_r, load_weight_r;

    integer k;

    // ----------------------------------------------------------------
    // Control mapping
    // We latch controls on each accepted input row.
    // If your design assumes control stays constant over many rows,
    // this is fine as long as the sender behaves consistently.
    // ----------------------------------------------------------------
    assign transpose_col_major = ~major_mode_r;
    assign sys_row_major       =  major_mode_r;
    assign sys_load_B          =  load_weight_r;

    generate
        genvar i;
        for (i = 0; i < DIM_p; i++) begin : g_tp_in
            assign transpose_in_data[i] = in_row_data[i];
        end
    endgenerate

    // Stream rows directly in when accepted
    assign transpose_valid_i = v_i & ready_o;
    assign input_fire        = v_i & ready_o;

    // Backpressure input if:
    // - node disabled
    // - transpose cannot accept
    // - systolic cannot accept transpose output path
    // - output register already full and we don't want unchecked overflow
    assign ready_o = en_i
                   & transpose_ready_o
                   & sys_transposer_ready
                   & (~out_valid_r | yumi_i);

    // Output interface to ring
    assign v_o    = out_valid_r;
    assign data_o = out_pkt_r;

    // Systolic can present a completed result when output holding reg is free,
    // or when the current packet is being consumed this cycle.
    assign sys_output_ready = (~out_valid_r) | (out_valid_r & yumi_i);

    // ----------------------------------------------------------------
    // Output packet formatting / hold logic
    // ----------------------------------------------------------------
    always_comb begin
        out_pkt_n   = out_pkt_r;
        out_valid_n = out_valid_r;

        if (out_valid_r && yumi_i) begin
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

            out_pkt_n[64]     = major_mode_r;
            out_pkt_n[65]     = load_weight_r;

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
            major_mode_r   <= 1'b0;
            load_weight_r  <= 1'b0;
        end
        else begin
            out_pkt_r   <= out_pkt_n;
            out_valid_r <= out_valid_n;

            // Latch current control bits on each accepted row
            if (input_fire) begin
                major_mode_r  <= in_major_mode;
                load_weight_r <= in_load_weight;
            end
        end
    end

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
        .clk                     (clk_i),
        .reset                   (reset_i),
        .load_B                  (sys_load_B),
        .row_major               (sys_row_major),
        .transposer_data         (transpose_out_data),
        .A_out_right             (A_out_right),
        .PS_out_right            (PS_out_right),
        .transposer_valid_in     (transpose_valid_o),
        .transposer_ready_out    (sys_transposer_ready),
        .output_buffer_ready_in  (sys_output_ready),
        .output_buffer_valid_out (sys_output_valid)
    );

endmodule