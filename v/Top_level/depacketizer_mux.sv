// depacketizer mux to control header flit traffic.
// one hot mux, assumes no resource contention.
// packets coming from write and exec are always size of 1
module depacketizer_mux #(
     parameter int packet_width_p = 128
    ,parameter int flit_width_p = 32
    ,localparam int num_flits_lp = packet_width_p / flit_width_p
    ,localparam int flit_cnt_width_lp = $clog2(num_flits_lp) + 1
) (
     input logic [packet_width_p-1:0]         read_packet_i
    ,input logic                             read_valid_i
    ,input logic [flit_cnt_width_lp-1:0]      read_packet_size_i
    ,output logic                            read_ready_o

    ,input logic [flit_width_p-1:0]           write_packet_i
    ,input logic                              write_valid_i
    ,output logic                             write_ready_o

    ,input logic [flit_width_p-1:0]           exec_packet_i
    ,input logic                              exec_valid_i
    ,output logic                             exec_ready_o

    ,output logic [packet_width_p-1:0]        packet_o
    ,output logic                             valid_o
    ,output logic [flit_cnt_width_lp-1:0]     packet_size_o
    ,input  logic                             ready_i
);

    assign read_ready_o = ready_i;
    assign write_ready_o = ready_i;
    assign exec_ready_o = ready_i;

    always_comb begin
        packet_o = '0;
        packet_size_o = '0;
        valid_o = '0;

        if (read_valid_i) begin
            packet_o = read_packet_i;
            packet_size_o = read_packet_size_i;
            valid_o = '1;
        end else if (write_valid_i) begin
            packet_o = {write_packet_i, 224'b0};
            packet_size_o = 1;
            valid_o = '1;
        end else if (exec_valid_i) begin
            packet_o = {exec_packet_i, 224'b0};
            packet_size_o = 1;
            valid_o = '1;
        end
    end

endmodule
