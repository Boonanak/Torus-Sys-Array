/* Power monitor provides an I2C interface wrapper that makes I2C
	register read requests to read the power data off of the INA322 power monitor chip
	
	It reads both channel 1 and channel 2 with a single request, and converts the value into
	mW in binary. 
	
	Set ready_i high with ready_o is high to begin a request. This process will take several clock cycles
	Data is valid when valid_o is asserted. Note that on reset valid_o will be asserted even though
	no request for data has been made.
*/

module power_monitor (
	input logic clk,
	input logic rst,
	
	input logic ready_i,
	output logic valid_o,
	output logic ready_o,
	
	output logic [31:0] ch1_power_mW,
	output logic [31:0] ch2_power_mW,
	
	inout wire sda,
	inout wire scl
);
	
	// channel request connections
	logic channel, request_start, request_valid, request_ready;
	logic [31:0] ch1_pwr_mW_r, ch2_pwr_mW_r; // latched for each output
	logic [31:0] ch_pwr_mW_r;
	
	// FSM states
	enum logic [2:0] {IDLE, CH1_REQUEST, CH1_READ, CH2_REQUEST, CH2_READ, OUTPUT} curr, next;
	
	// Next state logic
	always_comb begin
		channel = 1'b0;
		request_start = 1'b0;
		case(curr)
			IDLE: next = (ready_i && request_ready) ? CH1_REQUEST : IDLE;
			CH1_REQUEST: begin 
				next = CH1_READ;
				channel = 1'b0;
				request_start = 1'b1;
			end
			CH1_READ: begin
				next = (request_valid) ? CH2_REQUEST : CH1_READ;
				channel = 1'b0;
				request_start = 1'b0;
			end
			CH2_REQUEST: begin
				next = CH2_READ;
				channel = 1'b1;
				request_start = 1'b1;
			end
			CH2_READ: begin
				next = (request_valid) ? OUTPUT : CH2_READ;
				channel = 1'b1;
				request_start = 1'b0;
			end
			OUTPUT: next = IDLE;
			default: next = IDLE;
		endcase
	end
	
	// State Advancement
	always_ff @(posedge clk) begin
		if (rst) begin
			curr <= IDLE;
		end else begin
			curr <= next;
		end // else
	end // always_ff
	
	// Data storing from channel requestor
	always_ff @(posedge clk) begin
		case(curr)
			CH1_READ: ch1_power_mW <= ch_pwr_mW_r; // keep assigning, the final value will be set once it is valid and moves on
			CH2_READ: ch2_power_mW <= ch_pwr_mW_r;
			default: ;
		endcase
	end
	
	// Channel requestor, gets the power for a specific channel
	channel_request ch_req (
		.clk (clk),
		.rst (rst),
		.channel_i (channel),
		.ready_i (request_start),
		.ready_o (request_ready),
		.valid_o (request_valid),
		.ch_pwr_mW_o (ch_pwr_mW_r),
		.sda (sda),
		.scl (scl)
	);
	
	assign ready_o = curr == IDLE;
	assign valid_o = curr == IDLE;
	

endmodule 