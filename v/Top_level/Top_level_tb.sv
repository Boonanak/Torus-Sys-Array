`timescale 1ns/1ps

import PE_pkg::*;

module Top_level_tb;

  localparam int ring_width_p = 32;
  localparam int out_width_p  = 64;
  localparam int id_p         = 0;
  localparam int DIM_p        = 4;
  localparam int WIDTH_p      = 8;

  typedef logic signed [7:0]  elem8_t;
  typedef logic signed [15:0] elem16_t;

  logic                    clk_i;
  logic                    reset_i;

  logic                    v_i;
  logic [ring_width_p-1:0] data_i;
  logic                    ready_o;
  logic                    in_major_mode;
  logic                    in_load_weight;

  logic                    v_o;
  logic [out_width_p-1:0]  data_o;
  logic                    ready_i;

  Top_level #(
    .ring_width_p(ring_width_p),
    .out_width_p (out_width_p),
    .id_p        (id_p),
    .DIM_p       (DIM_p),
    .WIDTH_p     (WIDTH_p)
  ) dut (
    .clk_i          (clk_i),
    .reset_i        (reset_i),
    .v_i            (v_i),
    .data_i         (data_i),
    .ready_o        (ready_o),
    .in_major_mode  (in_major_mode),
    .in_load_weight (in_load_weight),
    .v_o            (v_o),
    .data_o         (data_o),
    .ready_i        (ready_i)
  );

  elem8_t  A     [0:DIM_p-1][0:DIM_p-1];
  elem8_t  B     [0:DIM_p-1][0:DIM_p-1];
  elem16_t C_exp [0:DIM_p-1][0:DIM_p-1];
  elem16_t C_got [0:DIM_p-1][0:DIM_p-1];

  integer out_count;
  integer i, j, k;

  // ---------------- Clock ----------------
  initial clk_i = 1'b0;
  always #20 clk_i = ~clk_i;

  initial begin
    $fsdbDumpfile("waveform.fsdb");
    $fsdbDumpvars(0, Top_level_tb, "+all");
  end

  // ---------------- Helpers ----------------
  function automatic logic [31:0] pack_row(
    input elem8_t d0,
    input elem8_t d1,
    input elem8_t d2,
    input elem8_t d3
  );
    begin
      pack_row[7:0]   = d0;
      pack_row[15:8]  = d1;
      pack_row[23:16] = d2;
      pack_row[31:24] = d3;
    end
  endfunction

  task automatic compute_golden;
    integer r, c, t;
    integer sum;
    begin
      for (r = 0; r < DIM_p; r++) begin
        for (c = 0; c < DIM_p; c++) begin
          sum = 0;
          for (t = 0; t < DIM_p; t++) begin
            sum = sum + A[r][t] * B[t][c];
          end
          C_exp[r][c] = sum;
        end
      end
    end
  endtask

  task automatic print_matrix8(
    input string name,
    input elem8_t M [0:DIM_p-1][0:DIM_p-1]
  );
    integer r, c;
    begin
      $display("%s =", name);
      for (r = 0; r < DIM_p; r++) begin
        $write("[ ");
        for (c = 0; c < DIM_p; c++) begin
          $write("%0d ", M[r][c]);
        end
        $write("]\n");
      end
    end
  endtask

  task automatic print_matrix16(
    input string name,
    input elem16_t M [0:DIM_p-1][0:DIM_p-1]
  );
    integer r, c;
    begin
      $display("%s =", name);
      for (r = 0; r < DIM_p; r++) begin
        $write("[ ");
        for (c = 0; c < DIM_p; c++) begin
          $write("%0d ", M[r][c]);
        end
        $write("]\n");
      end
    end
  endtask

  // Send an entire 4-row matrix in a contiguous burst.
  // If ready_o stays high, one row is accepted every clock cycle.
  task automatic send_matrix_burst(
    input logic   load_weight,
    input logic   major_mode,
    input elem8_t M [0:DIM_p-1][0:DIM_p-1]
  );
    integer r;
    logic [31:0] pkt;
    begin
      r = 0;

      // Put first row on the bus before the first handshake edge
      @(negedge clk_i);
      pkt             = pack_row(M[r][0], M[r][1], M[r][2], M[r][3]);
      v_i             <= 1'b1;
      data_i          <= pkt;
      in_load_weight  <= load_weight;
      in_major_mode   <= major_mode;

      while (r < DIM_p) begin
        @(posedge clk_i);

        if (v_i && ready_o) begin
          $display("Sent row %0d at time %0t : [%0d %0d %0d %0d]  load_weight=%0b major_mode=%0b",
                   r, $time,
                   M[r][0], M[r][1], M[r][2], M[r][3],
                   load_weight, major_mode);

          r = r + 1;

          if (r < DIM_p) begin
            @(negedge clk_i);
            pkt             = pack_row(M[r][0], M[r][1], M[r][2], M[r][3]);
            v_i             <= 1'b1;
            data_i          <= pkt;
            in_load_weight  <= load_weight;
            in_major_mode   <= major_mode;
          end
        end
      end

      @(negedge clk_i);
      v_i             <= 1'b0;
      data_i          <= '0;
      in_load_weight  <= 1'b0;
      in_major_mode   <= 1'b0;
    end
  endtask

  // ---------------- Output capture ----------------
  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      out_count <= 0;
      for (int r = 0; r < DIM_p; r++) begin
        for (int c = 0; c < DIM_p; c++) begin
          C_got[r][c] <= '0;
        end
      end
    end
    else begin
      if ((v_o === 1'b1) && (ready_i === 1'b1)) begin
        if (out_count < DIM_p) begin
          C_got[out_count][0] <= $signed(data_o[15:0]);
          C_got[out_count][1] <= $signed(data_o[31:16]);
          C_got[out_count][2] <= $signed(data_o[47:32]);
          C_got[out_count][3] <= $signed(data_o[63:48]);

          $display("Captured output row %0d at time %0t : [%0d %0d %0d %0d]",
                   out_count, $time,
                   $signed(data_o[15:0]),
                   $signed(data_o[31:16]),
                   $signed(data_o[47:32]),
                   $signed(data_o[63:48]));

          out_count <= out_count + 1;
        end
      end
    end
  end

  // ---------------- Stimulus ----------------
  initial begin
    // Init interface
    reset_i        = 1'b1;
    v_i            = 1'b0;
    data_i         = '0;
    in_major_mode  = 1'b0;
    in_load_weight = 1'b0;
    ready_i        = 1'b1;

    // Example matrices
    // A = data
    A[0][0] =  1; A[0][1] =  1; A[0][2] =  1; A[0][3] =  1;
    A[1][0] =  0; A[1][1] =  0; A[1][2] =  0; A[1][3] =  0;
    A[2][0] =  0; A[2][1] =  0; A[2][2] =  0; A[2][3] =  0;
    A[3][0] =  0; A[3][1] =  0; A[3][2] =  0; A[3][3] =  0;

    // B = weights
    B[0][0] =  1;  B[0][1] =  0;  B[0][2] =  0;  B[0][3] =  0;
    B[1][0] =  0;  B[1][1] =  1;  B[1][2] =  0;  B[1][3] =  0;
    B[2][0] =  0;  B[2][1] =  0;  B[2][2] =  1;  B[2][3] =  0;
    B[3][0] =  0;  B[3][1] =  0;  B[3][2] =  0;  B[3][3] =  1;

    compute_golden();

    print_matrix8("A (data)", A);
    print_matrix8("B (weights)", B);
    print_matrix16("Expected C = A*B", C_exp);

    // Reset
    repeat (5) @(posedge clk_i);
    reset_i = 1'b0;
    repeat (2) @(posedge clk_i);

    // Send weights and data back-to-back
    $display("Sending weight matrix B...");
    send_matrix_burst(1'b1, 1'b0, B);

    $display("Sending data matrix A...");
    send_matrix_burst(1'b0, 1'b0, A);

    // Wait for 4 output rows
    begin : wait_for_outputs
      integer timeout;
      timeout = 0;
      while (out_count < DIM_p && timeout < 500) begin
        @(posedge clk_i);
        timeout = timeout + 1;
      end
      
      if (out_count < DIM_p) begin
        $error("Timed out waiting for all outputs. Only received %0d rows.", out_count);
        $finish;
      end
    end
    repeat (50) @(posedge clk_i);
    // Compare results
    print_matrix16("Captured C_got", C_got);

    for (i = 0; i < DIM_p; i++) begin
      for (j = 0; j < DIM_p; j++) begin
        if (C_got[i][j] !== C_exp[i][j]) begin
          $error("Mismatch at C[%0d][%0d]: got %0d expected %0d",
                 i, j, C_got[i][j], C_exp[i][j]);
          $finish;
        end
      end
    end

    $display("PASS: all 4x4 outputs matched expected A*B result.");
    $finish;
  end

endmodule