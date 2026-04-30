// MODULE IS WORK IN PROGRESS
// Upstream is output
// Downstream is input
module functional_top #(
                        parameter PACKET_WIDTH_p = 128,
                        parameter FLIT_WIDTH_p = 32,
                        parameter FIFO_ELS_p = 4,
                        parameter PARITY_DATA_WIDTH_p = 17,
                        parameter NUM_CHANNELS_p = 1,
                        parameter DATA_WIDTH_p = 16,
                        localparam PACKET_LENGTH_p = $clog2(PACKET_WIDTH_p / FLIT_WIDTH_p) // how many bits needed to break a packet into flits
                      ) (
                        // System Inputs
                        input logic core_clk_i,
                        input logic reset_n_i,
                        input logic chicken_1,
                        input logic chicken_2,

                        // Debug inputs (placeholder names)
                        input logic debug_1,
                        input logic debug_2,
                        input logic debug_3,
                        input logic debug_4,

                        // Data Input
                        input logic bsg_link_downstream_clk,
                        input logic bsg_link_downstream_valid,
                        input logic bsg_link_downstream_yumi,
                        input logic bsg_link_downstream_parity,
                        input logic [DATA_WIDTH_p-1:0] bsg_link_downstream_data,

                        // Data Output
                        output logic bsg_link_upstream_clk,
                        output logic bsg_link_upstream_valid,
                        output logic bsg_link_upstream_yumi,
                        output logic bsg_link_upstream_parity,
                        output logic [DATA_WIDTH_p-1:0] bsg_link_upstream_data,
                      );  

    // Downstream side
    logic downstream_valid, datapath_ready, parity_check; 
    logic [FLIT_WIDTH_p-1:0] bsg_link_downstream_flit;
    logic [PARITY_DATA_WIDTH_p-1:0] bsg_link_downstream_parity_data;
    assign bsg_link_upstream_parity_data = {bsg_link_upstream_parity, bsg_link_upstream_data}; 

    // Upstream side
    logic upstream_ready, datapath_valid; 
    logic [PACKET_WIDTH_p-1:0] output_data_packet;
    logic [PACKET_LENGTH_p:0] packet_length;
    logic [PARITY_DATA_WIDTH_p-1:0] bsg_link_upstream_parity_data;
    assign bsg_link_downstream_parity_data = {bsg_link_downstream_parity, bsg_link_downstream_data};

    // Most of the chip design, houses the memory and functional parts of the chip.
    // Signals are WIP
    datapath dp1 ();

    // Wrapper for the output module
    upstream_wrapper #(.packet_width_p(PACKET_WIDTH_p), 
                       .flit_width_p(FLIT_WIDTH_p), 
                       .fifo_els_p(FIFO_ELS_p), 
                       .channel_width(PARITY_DATA_WIDTH_p), 
                       .num_channels_p(NUM_CHANNELS_p)
                      ) 
                       us1
                      (.core_clk_i(core_clk_i), 
                       .core_reset_i(reset_n_i), 
                       .packet_i(output_data_packet), 
                       .valid_i(datapath_valid), 
                       .packet_size_i(packet_length),
                       .ready_o(upstream_ready),
                       .io_clk_i(core_clk_i),
                       .io_link_reset_i(/*MISSING*/),
                       .async_token_reset_i(/*MISSING*/),
                       .io_clk_r_o(bsg_link_upstream_clk),
                       .io_data_r_o(bsg_link_upstream_parity_data),
                       .io_valid_r_o(bsg_link_upstream_valid),
                       .token_clk_i(bsg_link_upstream_yumi)
                       );

    // Wrapper for the input module
    downstream_wrapper #(.flit_width_p(FLIT_WIDTH_p),
                         .channel_width(PARITY_DATA_WIDTH_p),
                         .num_channels_p(NUM_CHANNELS_p)
                        ) 
                         ds1
                        (.core_clk_i(core_clk_i), 
                         .core_reset_i(reset_n_i), 
                         .flit_o(bsg_link_downstream_flit),
                         .valid_o(downstream_valid),
                         .ready_i(datapath_ready),
                         .parity_error_o(parity_check),
                         .io_clk_i(bsg_link_downstream_clk),
                         .io_link_reset_i(/*MISSING*/),
                         .io_data_i(bsg_link_downstream_parity_data),
                         .io_valid_i(bsg_link_downstream_valid),
                         .token_clk_o(bsg_link_downstream_yumi)
                        );

  // Wrapper for the debug interface


endmodule