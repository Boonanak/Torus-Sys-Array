module channel_request (
	input logic clk,
	input logic rst,
	
	input logic channel_i, // Which channel to send a request to, 0 = ch1, 1 = ch2
	
	input logic ready_i,
	output logic ready_o,
	output logic valid_o,
	output logic [31:0] ch_pwr_mW_o,
	
	inout wire sda,
	inout wire scl
);

/*
		These magic numbers are calculated as follows:
		
		Shunt Resistance R = 100 mOhms (nominal shunt resistance) 			
		Shunt uV per count constant S_c = 40 uV / count (from INA332126V datasheet)
		Vbus mV per count constant B_c = 8 mV / count 	(from INA332126V datasheet)
		
		magic number P_c = (S_c * B_c) / (R * 1000)      (1000 converts magnitude to mW)
						 P_c = 2 / 625 mW
						 
		This turns into a left shift by 1 (which is the same as *2)
		and a divide by 625, and the result is in mW.
		
		Multiplying the raw shunt_counts by bus_counts, and performing the shift and divide gets the power for that channel
	*/
	localparam int POWER_SHIFT = 1;
	localparam int POWER_DIVISOR = 625;
	
	// Register addresses for each voltage reading
	localparam logic [7:0] CH1_SHUNT_ADDR = 7'h1;
	localparam logic [7:0] CH1_BUS_ADDR   = 7'h2;
	localparam logic [7:0] CH2_SHUNT_ADDR = 7'h3;
	localparam logic [7:0] CH2_BUS_ADDR   = 7'h4;
	
	// I2C address of device
	localparam logic [6:0] DEVICE_ADDRESS = 7'h40;
	
	// Clock Divider equation
	localparam int CLOCK_SPEED_HZ     = 50_000_000;
	localparam int I2C_CLOCK_SPEED_HZ = 400_000; // target I2C Clock speed
	localparam int DIVIDER = ((CLOCK_SPEED_HZ + (4*I2C_CLOCK_SPEED_HZ) - 1) / (4*I2C_CLOCK_SPEED_HZ)) - 1;

	// I2C Signals
	logic enable, busy;
	logic [15:0] data_in, data_out;
	logic [7:0] register_address;
	
	// Internal Signals
	logic [15:0] ch_shunt_counts, ch_bus_counts;
	logic [31:0] ch_power_mW_r;
	logic channel_r;
	
	enum logic [2:0] {IDLE, REQUEST_SHUNT, READ_SHUNT, REQUEST_BUS, READ_BUS, COMPUTE} curr, next;
	
	// Next state advancement
	always_comb begin
		case(curr)
			IDLE: next = (ready_i && !busy) ? REQUEST_SHUNT : IDLE;
			REQUEST_SHUNT: next = READ_SHUNT;
			READ_SHUNT: next = busy ? READ_SHUNT : REQUEST_BUS;
			REQUEST_BUS: next = READ_BUS;
			READ_BUS: next = busy ? COMPUTE : READ_BUS;
			COMPUTE: next = IDLE;
		endcase
	end // always_comb
	
	// State Advancement
	always_ff @(posedge clk) begin
		data_in <= '0; // data is never written
		if (rst) begin
			curr <= IDLE;
		end else begin 
			curr <= next;
		end // else
	end // always_ff
	
	// I2C command stimulus
	always_ff @(posedge clk) begin
		case(curr)
			IDLE: begin
				channel_r <= channel_i;
			end // IDLE
			REQUEST_SHUNT: begin
				register_address <= channel_r ? CH2_SHUNT_ADDR : CH1_SHUNT_ADDR;
				enable <= 1'b1;
			end // REQUEST_SHUNT
			READ_SHUNT: begin
				enable <= 1'b0;
				ch_shunt_counts <= data_out; // read every cycle, the true value will be regsistered when it goes to !busy
			end // READ_SHUNT
			REQUEST_BUS: begin
				register_address <= channel_r ? CH2_BUS_ADDR : CH1_BUS_ADDR;
				enable <= 1'b1;
			end // REQUEST_BUS
			READ_BUS: begin
				enable <= 1'b0;
				ch_bus_counts <= data_out; 
			end // READ_BUS
			COMPUTE: begin
				ch_pwr_mW_o <= ( (ch_shunt_counts * ch_bus_counts) << POWER_SHIFT) / POWER_DIVISOR;
			end // COMPUTE
		endcase
	end // always_ff
	
	i2c_master #(
		 .NUMBER_OF_DATA_BYTES           (2),
		 .NUMBER_OF_REGISTER_BYTES       (1),
		 .ADDRESS_WIDTH                  (7),
		 .CHECK_FOR_CLOCK_STRETCHING     (1),
		 .CLOCK_STRETCHING_TIMER_WIDTH	 (16),
		 .CLOCK_STRETCHING_MAX_COUNT     ('hFF)
	)
	i2c_master_inst(
		 .clock                  (clk),
		 .reset_n                (~rst),
		 .enable                 (enable),
		 .read_write             (1'b1), // always reading
		 .mosi_data              (data_in),
		 .register_address       (register_address),
		 .device_address         (DEVICE_ADDRESS),
		 .divider                (DIVIDER),

		 .miso_data              (data_out),
		 .busy                   (busy),

		 .external_serial_data   (sda),
		 .external_serial_clock  (scl)
	); // i2c_master
	
	assign ready_o = curr == IDLE;
	assign valid_o = curr == IDLE;

endmodule // channel_request