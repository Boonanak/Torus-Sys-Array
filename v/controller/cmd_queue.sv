
import ctrl_pkg::*;

module cmd_queue #(
     parameter int DEPTH_p = 8
    ,localparam int PTR_W_lp = $clog2(DEPTH_p)
)(
     input  logic          clk_i
    ,input  logic          reset_i

    ,input  decoded_cmd_t  enq_data_i
    ,input  logic          enq_v_i
    ,output logic          enq_ready_o

    ,output decoded_cmd_t  deq_data_o
    ,output logic          deq_v_o
    ,input  logic          deq_ready_i

    ,output logic          empty_o
);

    decoded_cmd_t fifo_r [DEPTH_p-1:0];
    logic [PTR_W_lp-1:0] rptr_r, wptr_r;
    logic [PTR_W_lp:0]   count_r;

    logic full, empty;
    assign full     = (count_r == DEPTH_p);
    assign empty    = (count_r == 0);
    assign empty_o  = empty;

    assign enq_ready_o = ~full;
    assign deq_v_o     = ~empty;
    assign deq_data_o  = fifo_r[rptr_r];

    logic enq_fire, deq_fire;
    assign enq_fire = enq_v_i     & enq_ready_o;
    assign deq_fire = deq_ready_i & deq_v_o;

    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            rptr_r  <= '0;
            wptr_r  <= '0;
            count_r <= '0;
        end else begin
            if (enq_fire) begin
                fifo_r[wptr_r] <= enq_data_i;
                wptr_r         <= (wptr_r == DEPTH_p-1) ? '0 : wptr_r+1;
            end
            if (deq_fire) begin
                rptr_r         <= (rptr_r == DEPTH_p-1) ? '0 : rptr_r+1;
            end
            case ({enq_fire, deq_fire})
                2'b10: count_r <= count_r + 1;
                2'b01: count_r <= count_r - 1;
                default: ;
            endcase
        end
    end

endmodule
