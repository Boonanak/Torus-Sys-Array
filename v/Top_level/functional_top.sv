// MODULE IS WORK IN PROGRESS
// Upstream is output
// Downstream is input
module functional_top #(
                        parameter int PACKET_WIDTH_p = 256,
                        parameter int FLIT_WIDTH_p = 32,
                        parameter int FIFO_ELS_p = 4,
                        parameter int PARITY_DATA_WIDTH_p = 17,
                        parameter int NUM_CHANNELS_p = 1,
                        parameter int DATA_WIDTH_p = 16,
                        parameter int DIM_p = 8,
                        parameter int NUM_MATRICES_p = 4,
                        parameter int CMDQ_DEPTH_p = 8,
                        // how many bits needed to break a packet into flits
                        localparam int PACKET_LENGTH_p = $clog2(PACKET_WIDTH_p / FLIT_WIDTH_p)
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
                        output logic [DATA_WIDTH_p-1:0] bsg_link_upstream_data
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
    top_chip #(
                   .DIM_p(DIM_p),
                   .NUM_MATRICES_p(NUM_MATRICES_p),
                   .CMDQ_DEPTH_p(CMDQ_DEPTH_p),
                   .PACKET_WIDTH_p(PACKET_WIDTH_p)
                  ) tc1 (
                   .clk_i(core_clk_i),
                   .reset_i(reset_n_i), // ENSURE ALL MODULES USE ACTIVE LOW RESET
                   .link_in_v_i(downstream_valid),
                   .link_in_data_i(bsg_link_downstream_flit),
                   .link_in_parity_i(parity_check),
                   .link_in_yumi_o(datapath_ready),
                   .link_out_v_o(datapath_valid),
                   .link_out_data_o(output_data_packet),
                   .link_out_packet_size_o(packet_length),
                   .link_out_yumi_i(upstream_ready)
                  );


    // Wrapper for the output module
    upstream_wrapper #(.packet_width_p(PACKET_WIDTH_p),
                       .flit_width_p(FLIT_WIDTH_p),
                       .fifo_els_p(FIFO_ELS_p),
                       .channel_width(PARITY_DATA_WIDTH_p),
                       .num_channels_p(NUM_CHANNELS_p)
                      )
                       usw1
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
                         dsw1
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
