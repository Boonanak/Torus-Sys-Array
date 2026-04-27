// LARDI (Low Area and Routing Debug Interface) Controller
// This module implements a simple state machine to control the LARDI interface.
// The lardi interface is designed to be a very small externally facing interface
// for accessing internal registers for debugging purposes. 
// lardi_cmd is the serial input to select which client is the data source
// lardi_client_data_i is the parallel input from each client, only one will be selected at a time
// lardi_data_o is the serial output of the selected client data, buffered through a shift register
module lardi_controller #(
    parameter BUFFER_LENGTH_p = 1, // length of shift register buffer, should be at least 1.
    parameter NUM_CLIENTS_p = 4, // number of clients that can be selected, can be aribitrairy 
    localparam NUM_CLIENTS_BITWIDTH_lp = $clog2(NUM_CLIENTS_p) // number of bits needed to select among NUM_CLIENTS_p clients
) (
    input logic lardi_clk_i,
    input logic reset_n_i,
    input logic lardi_cmd,
    input logic [NUM_CLIENTS_p-1:0] lardi_client_data_i,
    output logic lardi_data_o
);

    logic [NUM_CLIENTS_BITWIDTH_lp-1:0] current_client, next_client;
    logic [NUM_CLIENTS_BITWIDTH_lp-1:0] cmd_counter;
    logic counter_reached;

    enum logic [1:0] state_e {IDLE, CMD_START, COUNTER_RESET, CMD_BUILD} curr, next;

    // Combinational logic to determine the next state based on the current state and inputs
    // IDLE simply outputs the current client data, and waits for a command
    // CMD_START waits for NUM_CLIENTS_BITWIDTH_lp bits of 1 to indicated a valid command 
    // COUNTER_RESET resets the counter to prepare for building the next client data
    // CMD_BUILD builds the command up from each bit of lardi_cmd.
    // Once the command has been complete, returns to IDLE with the new client selected.
    always_comb begin
        counter_reached = cmd_counter >= NUM_CLIENTS_BITWIDTH_lp;
        case(curr)
            IDLE:           next = lardi_cmd ? CMD_START : IDLE;
            CMD_START:      next = lardi_cmd ? (counter_reached ? COUNTER_RESET : CMD_START) : IDLE;
            COUNTER_RESET:  next = CMD_BUILD;
            CMD_BUILD:      next = counter_reached ? IDLE : CMD_BUILD;
            default:        next = IDLE;
        endcase
    end

    // Sequential logic to update the state and counters
    // waits for command with is NUM_CLIENTS_BITWIDTH_lp bits of 1. 
    // the next NUM_CLIENTS_BITWIDTH_lp bits will be the command
    // Set the command as the new client data source.
    always_ff @(posedge lardi_clk_i or negedge reset_n_i) begin
        if (!reset_n_i) begin
            current_client <= '0;
            next_client <= '0;
            cmd_counter <= '0;
            curr <= IDLE;
        end else begin
            case (curr)
                IDLE: begin 
                    cmd_counter <= '0;
                    // ensure the client is within bounds, if not default to client 0
                    current_client <= next_client >= NUM_CLIENTS_p ? '0 : next_client; 
                end
                CMD_START: begin 
                    cmd_counter <= cmd_counter + 1;
                end
                COUNTER_RESET: begin // needed to ensure the next state starts with a clean counter
                    cmd_counter <= '0;
                end
                CMD_BUILD: begin 
                    next_client[NUM_CLIENTS_BITWIDTH_lp - 1 - cmd_counter] <= lardi_cmd;
                    cmd_counter <= cmd_counter + 1;
                end
            endcase
        end
    end
    
    // Buffer on the output to shift out the client data one at a time
    serial_shifter #(
        .WIDTH_p(1),
        .LENGTH_p(BUFFER_LENGTH_p)
    ) shift_reg (
        .clk_i(lardi_clk_i),
        .rst_n_i(reset_n_i),
        .enable_i(1'b1),
        .shift_in_i(lardi_client_data_i[current_client]),
        .data_out_o(lardi_data_o)
    );

endmodule