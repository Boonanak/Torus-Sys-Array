
module link16_to_flit32 (
     input  logic        clk_i
    ,input  logic        reset_i

    ,input  logic [15:0] link_data_i
    ,input  logic        link_v_i
    ,input  logic        link_parity_i  // even-parity bit
    ,output logic        link_yumi_o

    ,output logic [31:0] flit_o
    ,output logic        flit_v_o
    ,output logic        flit_parity_ok_o
    ,input  logic        flit_ready_i
);

    logic [15:0] hi_r;
    logic        hi_par_ok_r;  // parity ok of upper half
    logic        have_hi_r;  // upper captured, waiting for lower

    logic        link_par_ok;  // even-parity check this transfer
    assign link_par_ok = (^link_data_i) ~^ link_parity_i;

    logic emit_now;
    assign emit_now = link_v_i & have_hi_r;

    assign link_yumi_o = link_v_i &
                         (have_hi_r ? flit_ready_i : 1'b1);

    assign flit_v_o          = emit_now;
    assign flit_o            = {hi_r, link_data_i};  // hi first, lo second
    assign flit_parity_ok_o  = hi_par_ok_r & link_par_ok;  // both halves OK

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            hi_r        <= '0;
            hi_par_ok_r <= 1'b0;
            have_hi_r   <= 1'b0;
        end else begin
            if (link_yumi_o) begin  // a transfer fired
                if (have_hi_r) begin  // was lower half
                    have_hi_r <= 1'b0;  // reset
                end else begin  // was upper half
                    hi_r        <= link_data_i;
                    hi_par_ok_r <= link_par_ok;
                    have_hi_r   <= 1'b1;
                end
            end
        end
    end

endmodule
