
module flit32_to_link16 (
     input  logic        clk_i
    ,input  logic        reset_i

    ,input  logic [31:0] flit_i
    ,input  logic        flit_v_i
    ,output logic        flit_ready_o

    ,output logic [15:0] link_data_o
    ,output logic        link_v_o
    ,output logic        link_parity_o
    ,input  logic        link_yumi_i
);

    logic sent_hi_r;

    assign link_data_o   = sent_hi_r ? flit_i[15:0]  : flit_i[31:16];  // hi first
    assign link_parity_o = ^link_data_o;  // even parity (XOR reduction)
    assign link_v_o      = flit_v_i;  // valid until both halves drained

    assign flit_ready_o  = flit_v_i & link_yumi_i & sent_hi_r;

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            sent_hi_r <= 1'b0;
        end else if (link_v_o & link_yumi_i) begin
            sent_hi_r <= ~sent_hi_r;  // toggle each transfer
        end
    end

endmodule
