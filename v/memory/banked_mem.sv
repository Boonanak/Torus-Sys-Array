module banked_mem #(
    parameter TOTAL_ROWS = 256,
    parameter NUM_BANKS = 4,
    parameter REQUEST_BUFFER_DEPTH = 8,
    localparam TAG_LENGTH = $clog2(NUM_BANKS)
) (
     input  logic   clk_i
    ,input  logic   reset
    
    ,input  mem_pkg::r_req   read_request[0 : NUM_BANKS - 1]
    ,output mem_pkg::r_rsp   read_response[0 : NUM_BANKS - 1]
    
    ,input  mem_pkg::w_req   write_request[0 : NUM_BANKS - 1]
    ,output mem_pkg::w_rsp   write_response[0 : NUM_BANKS - 1]
);

    // address, data, wren used by each bank
    logic [mem_pkg::ADDR_LENGTH - 2 - 1 : 0] bank_read_addr     [0 : NUM_BANKS - 1];
    logic [mem_pkg::ADDR_LENGTH - 2 - 1 : 0] bank_write_addr    [0 : NUM_BANKS - 1];
    logic [mem_pkg::DATA_WIDTH - 1 : 0] bank_read_data  [0 : NUM_BANKS - 1];
    logic [mem_pkg::DATA_WIDTH - 1 : 0] bank_write_data [0 : NUM_BANKS - 1];
    logic [1:0] bank_wren   [0 : NUM_BANKS - 1];

    // combinational logic for bank conflict
    logic bank_read_busy    [0 : NUM_BANKS - 1];
    logic bank_write_busy   [0 : NUM_BANKS - 1];

    // tag to route bank outputs to output ports.
    logic [$clog2(NUM_BANKS) - 1 : 0] bank_read_tag     [0 : NUM_BANKS - 1];

    // successful read/write at each port
    logic port_read_success         [0 : NUM_BANKS - 1];
    logic port_read_success_next    [0 : NUM_BANKS - 1];
    logic port_write_success        [0 : NUM_BANKS - 1];
    logic port_write_success_next   [0 : NUM_BANKS - 1];
    
    // assign input read port requests into banks. conflicted request fails
    // read
    always_comb begin
        for (int i = 0; i < NUM_BANKS; i++) begin 
            bank_read_busy[i] = '0;
            bank_read_addr[i] = '0;
            bank_read_tag[i] = '0;
            port_read_success_next[i] = '0;
        end
        for (int i = 0; i < NUM_BANKS; i++) begin 
            logic [1:0] bank = read_request[i].addr.fields.bank;
            if (~bank_read_busy[bank] && read_request[i].valid) begin 
                bank_read_busy[bank] = 1'b1;
                bank_read_addr[bank] = {read_request[i].addr.fields.block_idx, 
                                        read_request[i].addr.fields.wl_offset,
                                        read_request[i].addr.fields.seg_sel};
                bank_read_tag[bank] = i;
                port_read_success_next[i] = 1'b1;
            end
            else begin 
                port_read_success_next[i] = 1'b0;
            end
        end
    end
    // write
    always_comb begin 
        for (int i = 0; i < NUM_BANKS; i++) begin 
            bank_write_busy[i] = '0;
            bank_wren[i] = '0;
            bank_write_data[i] = '0;
            bank_write_addr[i] = '0;
            port_write_success_next[i] = '0;
        end
        for (int i = 0; i < NUM_BANKS; i++) begin 
            logic [1:0] bank = write_request[i].addr.fields.bank;
            if (~bank_write_busy[bank] && write_request[i].valid) begin 
                bank_write_busy[bank] = 1'b1;
                bank_write_addr[bank] = {write_request[i].addr.fields.block_idx, 
                                         write_request[i].addr.fields.wl_offset,
                                         write_request[i].addr.fields.seg_sel};
                bank_wren[bank] = write_request[i].wren;
                bank_write_data[bank] = write_request[i].data;
                port_write_success_next[i] = 1'b1;
            end
            else begin 
                port_write_success_next[i] = 1'b0;
            end
        end
    end

    // register to match read/write 1 cycle delay on the memory
    always_ff @(posedge clk_i) begin 
        if (reset) begin 
            for (int i = 0; i < NUM_BANKS; i++) begin 
                port_read_success[i] <= '0;
                port_write_success[i] <= '0;
            end
        end else begin 
            port_read_success <= port_read_success_next;
            port_write_success <= port_write_success_next;
        end
    end

    // route bank outputs to correct port
    always_comb begin 
        for (int i = 0; i < NUM_BANKS; i++) begin 
            read_response[i].data = '0;
        end
        for (int i = 0; i < NUM_BANKS; i++) begin 
            read_response[i].valid = port_read_success[i];
            write_response[i].valid = port_write_success[i];
            for (int j = 0; j < NUM_BANKS; j++) begin 
                if (bank_read_tag[j] == i) read_response[i].data = bank_read_data[j];
            end
        end
    end
    
    // instantiate banks
    generate 
        for (genvar i = 0; i < NUM_BANKS; i++) begin 
            partition_mem banks (
                 .clk_i(clk_i)
                ,.reset(reset)
                ,.read_addr_i(bank_read_addr[i][5:0])  // bottom bit ignored by partition_mem
                ,.write_addr_i(bank_write_addr[i][5:0]) // bottom bit ignored by partition_mem
                ,.wren_i(bank_wren[i])
                ,.write_data_i(bank_write_data[i])
                ,.read_data_o(bank_read_data[i])
            );
        end
    endgenerate

endmodule