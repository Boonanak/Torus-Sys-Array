`timescale 1ns/1ps

module Top_level_tb;

  localparam int ring_width_p = 75;
  localparam int id_p         = 0;
  localparam int DIM_p        = 4;
  localparam int WIDTH_p      = 8;

  logic                    clk_i;
  logic                    reset_i;
  logic                    en_i;

  logic                    v_i;
  logic [ring_width_p-1:0] data_i;
  logic                    ready_o;

  logic                    v_o;
  logic [ring_width_p-1:0] data_o;
  logic                    yumi_i;

  Top_level #(
    .ring_width_p(ring_width_p),
    .id_p        (id_p),
    .DIM_p       (DIM_p),
    .WIDTH_p     (WIDTH_p)
  ) dut (
    .clk_i   (clk_i),
    .reset_i (reset_i),
    .en_i    (en_i),
    .v_i     (v_i),
    .data_i  (data_i),
    .ready_o (ready_o),
    .v_o     (v_o),
    .data_o  (data_o),
    .yumi_i  (yumi_i)
  );

  initial clk_i = 0;
  always #5 clk_i = ~clk_i;

  logic signed [7:0]  A [0:DIM_p-1][0:DIM_p-1];
  logic signed [7:0]  B [0:DIM_p-1][0:DIM_p-1];
  logic signed [15:0] C_exp [0:DIM_p-1][0:DIM_p-1];

  integer out_count;
  integer r, c;

  function automatic [ring_width_p-1:0] make_input_pkt(
    input logic signed [7:0] d0,
    input logic signed [7:0] d1,
    input logic signed [7:0] d2,
    input logic signed [7:0] d3,
    input logic              major_mode,
    input logic              load_weight
  );
    logic [ring_width_p-1:0] pkt;
    begin
      pkt = '0;
      pkt[7:0]   = d0;
      pkt[15:8]  = d1;
      pkt[23:16] = d2;
      pkt[31:24] = d3;
      pkt[32]    = major_mode;
      pkt[33]    = load_weight;
      return pkt;
    end
  endfunction

  task automatic send_pkt(input logic [ring_width_p-1:0] pkt);
    begin
      @(posedge clk_i);
      while (!ready_o) @(posedge clk_i);

      v_i    <= 1'b1;
      data_i <= pkt;

      @(posedge clk_i);
      while (!(v_i && ready_o)) @(posedge clk_i);

      v_i    <= 1'b0;
      data_i <= '0;
    end
  endtask

  task automatic compute_expected;
    integer i, j, m;
    logic signed [31:0] sum;
    begin
      for (i = 0; i < DIM_p; i++) begin
        for (j = 0; j < DIM_p; j++) begin
          sum = 0;
          for (m = 0; m < DIM_p; m++) begin
            sum = sum + (A[i][m] * B[m][j]);
          end
          C_exp[i][j] = sum[15:0];
        end
      end
    end
  endtask

  task automatic check_output_pkt(
    input int row_idx,
    input logic [ring_width_p-1:0] pkt
  );
    logic signed [15:0] y0, y1, y2, y3;
    logic major_mode;
    logic load_weight;
    begin
      y0 = $signed(pkt[15:0]);
      y1 = $signed(pkt[31:16]);
      y2 = $signed(pkt[47:32]);
      y3 = $signed(pkt[63:48]);
      major_mode  = pkt[64];
      load_weight = pkt[65];

      $display("Output row %0d received: [%0d %0d %0d %0d], flags major=%0b load=%0b",
               row_idx, y0, y1, y2, y3, major_mode, load_weight);

      if (y0 !== C_exp[row_idx][0]) begin
        $error("Mismatch row %0d col 0: got %0d expected %0d",
               row_idx, y0, C_exp[row_idx][0]);
        $fatal;
      end
      if (y1 !== C_exp[row_idx][1]) begin
        $error("Mismatch row %0d col 1: got %0d expected %0d",
               row_idx, y1, C_exp[row_idx][1]);
        $fatal;
      end
      if (y2 !== C_exp[row_idx][2]) begin
        $error("Mismatch row %0d col 2: got %0d expected %0d",
               row_idx, y2, C_exp[row_idx][2]);
        $fatal;
      end
      if (y3 !== C_exp[row_idx][3]) begin
        $error("Mismatch row %0d col 3: got %0d expected %0d",
               row_idx, y3, C_exp[row_idx][3]);
        $fatal;
      end

      if (major_mode !== 1'b1) begin
        $error("Output row %0d major_mode incorrect: got %0b expected 1",
               row_idx, major_mode);
        $fatal;
      end
      if (load_weight !== 1'b0) begin
        $error("Output row %0d load_weight incorrect: got %0b expected 0",
               row_idx, load_weight);
        $fatal;
      end
    end
  endtask

  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      out_count <= 0;
    end else begin
      if (v_o && yumi_i) begin
        if (out_count < DIM_p) begin
          check_output_pkt(out_count, data_o);
          out_count <= out_count + 1;
        end else begin
          $error("Received more than %0d output packets", DIM_p);
          $fatal;
        end
      end
    end
  end

  initial begin
    #5000;
    $fatal("TIMEOUT: test did not finish");
  end

  initial begin
    reset_i = 1'b1;
    en_i    = 1'b0;
    v_i     = 1'b0;
    data_i  = '0;
    yumi_i  = 1'b1;

    // Signed example matrices
    B[0][0] =  8'sd1;  B[0][1] = -8'sd2;  B[0][2] =  8'sd3;  B[0][3] =  8'sd4;
    B[1][0] = -8'sd5;  B[1][1] =  8'sd6;  B[1][2] = -8'sd7;  B[1][3] =  8'sd8;
    B[2][0] =  8'sd1;  B[2][1] =  8'sd0;  B[2][2] = -8'sd1;  B[2][3] =  8'sd0;
    B[3][0] =  8'sd2;  B[3][1] = -8'sd1;  B[3][2] =  8'sd0;  B[3][3] = -8'sd2;

    A[0][0] =  8'sd1;  A[0][1] =  8'sd2;  A[0][2] = -8'sd3;  A[0][3] =  8'sd4;
    A[1][0] = -8'sd2;  A[1][1] =  8'sd1;  A[1][2] =  8'sd0;  A[1][3] =  8'sd1;
    A[2][0] =  8'sd3;  A[2][1] = -8'sd1;  A[2][2] =  8'sd2;  A[2][3] =  8'sd0;
    A[3][0] =  8'sd1;  A[3][1] =  8'sd0;  A[3][2] =  8'sd1;  A[3][3] = -8'sd2;

    compute_expected();

    $display("Expected C = A * B:");
    for (r = 0; r < DIM_p; r++) begin
      $display("[%0d %0d %0d %0d]",
        C_exp[r][0], C_exp[r][1], C_exp[r][2], C_exp[r][3]);
    end

    repeat (5) @(posedge clk_i);
    reset_i = 1'b0;
    en_i    = 1'b1;

    $display("Sending 4 weight rows...");
    send_pkt(make_input_pkt(B[0][0], B[0][1], B[0][2], B[0][3], 1'b1, 1'b1));
    send_pkt(make_input_pkt(B[1][0], B[1][1], B[1][2], B[1][3], 1'b1, 1'b1));
    send_pkt(make_input_pkt(B[2][0], B[2][1], B[2][2], B[2][3], 1'b1, 1'b1));
    send_pkt(make_input_pkt(B[3][0], B[3][1], B[3][2], B[3][3], 1'b1, 1'b1));

    $display("Sending 4 data rows...");
    send_pkt(make_input_pkt(A[0][0], A[0][1], A[0][2], A[0][3], 1'b1, 1'b0));
    send_pkt(make_input_pkt(A[1][0], A[1][1], A[1][2], A[1][3], 1'b1, 1'b0));
    send_pkt(make_input_pkt(A[2][0], A[2][1], A[2][2], A[2][3], 1'b1, 1'b0));
    send_pkt(make_input_pkt(A[3][0], A[3][1], A[3][2], A[3][3], 1'b1, 1'b0));

    wait (out_count == DIM_p);

    $display("PASS: received %0d correct signed output packets", DIM_p);
    #20;
    $finish;
  end

endmodule