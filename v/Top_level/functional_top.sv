
// MODULE IS WORK IN PROGRESS
// Upstream is output
// Downstream is input
module functional_top (
                        // General Inputs
                        input logic core_clk_i,
                        input logic reset_n_i,
                        input logic chicken_1,
                        input logic chicken_2,

                        // Debug inputs
                        input logic bsg_tag_en,
                        input logic bsg_tag_clk,
                        input logic bsg_tag_data,

                        // Input
                        input logic bsg_link_downstream_clk,
                        input logic bsg_link_downstream_valid,
                        input logic bsg_link_downstream_yumi,
                        input logic bsg_link_downstream_parity,
                        input logic [15:0] bsg_link_downstream_data,

                        // Output
                        output logic bsg_link_upstream_clk,
                        output logic bsg_link_upstream_valid,
                        output logic bsg_link_upstream_yumi, // UNUSED YET
                        output logic bsg_link_upstream_parity, // UNUSED YET
                        output logic [15:0] bsg_link_upstream_data,
                      );  

    logic [32:0] bsg_link_downstream_flit;
    logic [127:0] output_data_packet;
    logic [2:0] packet_length;
    logic depacketizer_ready, output_valid;

    // Most of the chip design, houses the memory and functional parts of the chip.
    // Signals are WIP
    datapath dp1 (core_clk, reset_n_i, bsg_link_downstream_flit, output_data_packet, packet_length, depacketizer_ready, output_valid);

    // Wrapper for the output module
    upstream_wrapper #(.packet_width_p(128), 
                       .flit_width_p(32), 
                       .fifo_els_p(4), 
                       .channel_width(16), 
                       .num_channels_p(1)
                       ) 
                       us1
                      (.core_clk_i(core_clk_i), 
                       .core_reset_i(reset_n_i), 
                       .packet_i(output_data_packet), 
                       .valid_i(output_valid), 
                       .ready_o(depacketizer_ready),
                       .io_clk_i(core_clk_i),
                       .io_link_reset_i(/*MISSING*/),
                       .async_token_reset_i(/*MISSING*/),
                       .io_clk_r_o(bsg_link_upstream_clk),
                       .io_data_r_o(bsg_link_upstream_data),
                       .io_valid_r_o(bsg_link_upstream_valid),
                       .token_clk_i(bsg_link_upstream_yumi),
                       );


endmodule