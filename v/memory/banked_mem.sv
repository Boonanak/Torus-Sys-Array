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
    logic [$clog2(NUM_BANKS) - 1 : 0] bank_read_tag_next [0 : NUM_BANKS - 1];

    // successful read/write at each port
    logic port_read_success         [0 : NUM_BANKS - 1];
    logic port_read_success_next    [0 : NUM_BANKS - 1];
    logic port_write_success        [0 : NUM_BANKS - 1];
    logic port_write_success_next   [0 : NUM_BANKS - 1];
    
    // assign input read port requests into banks. conflicted request fails
    // read
    always_comb begin
        int i;
        logic [1:0] bank [0 : NUM_BANKS - 1];

        for (i = 0; i < NUM_BANKS; i++) begin
            bank[i] = '0; 
            bank_read_busy[i] = '0;
            bank_read_addr[i] = '0;
            bank_read_tag_next[i] = '0;
            port_read_success_next[i] = '0;
        end
        for (i = 0; i < NUM_BANKS; i++) begin 
            bank[i] = read_request[i].addr.fields.bank;
            if (~bank_read_busy[bank[i]] && read_request[i].valid) begin 
                bank_read_busy[bank[i]] = 1'b1;
                bank_read_addr[bank[i]] = {read_request[i].addr.fields.block_idx, 
                                            read_request[i].addr.fields.wl_offset};
                bank_read_tag_next[bank[i]] = TAG_LENGTH'(i);
                port_read_success_next[i] = 1'b1;
            end
            else begin 
                port_read_success_next[i] = 1'b0;
            end
        end
    end
    // write
    always_comb begin
        int i; 
        logic [1:0] bank [0 : NUM_BANKS - 1];
        for (i = 0; i < NUM_BANKS; i++) begin 
            bank[i] = '0;
            bank_write_busy[i] = '0;
            bank_wren[i] = '0;
            bank_write_data[i] = '0;
            bank_write_addr[i] = '0;
            port_write_success_next[i] = '0;
        end
        for (i = 0; i < NUM_BANKS; i++) begin 
            bank[i] = write_request[i].addr.fields.bank;
            if (~bank_write_busy[bank[i]] && write_request[i].valid) begin 
                bank_write_busy[bank[i]] = 1'b1;
                bank_write_addr[bank[i]] = {write_request[i].addr.fields.block_idx, 
                                            write_request[i].addr.fields.wl_offset};
                bank_wren[bank[i]] = write_request[i].wren;
                bank_write_data[bank[i]] = write_request[i].data;
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
                bank_read_tag[i] <= '0;
            end
        end else begin 
            port_read_success <= port_read_success_next;
            port_write_success <= port_write_success_next;
            bank_read_tag <= bank_read_tag_next;
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
                if (bank_read_tag[j] == i) begin 
                    read_response[i].data = bank_read_data[j];
                    break;
                end
            end
        end
    end
    
    // instantiate banks
    generate 
        for (genvar i = 0; i < NUM_BANKS; i++) begin
            if (i == 2) begin 
                partition_mem #(
                    .HARD_CODE_ZERO(1)
                ) bank_2 (
                    .clk_i(clk_i)
                    ,.reset(reset)
                    ,.read_addr_i(bank_read_addr[i])
                    ,.write_addr_i(bank_write_addr[i])
                    ,.wren_i(bank_wren[i])
                    ,.write_data_i(bank_write_data[i])
                    ,.read_data_o(bank_read_data[i])
                );
            end else if (i == 3) begin 
                partition_mem #(
                    .HARD_CODE_IDENTITY(1)
                ) bank_3 (
                    .clk_i(clk_i)
                    ,.reset(reset)
                    ,.read_addr_i(bank_read_addr[i])
                    ,.write_addr_i(bank_write_addr[i])
                    ,.wren_i(bank_wren[i])
                    ,.write_data_i(bank_write_data[i])
                    ,.read_data_o(bank_read_data[i])
                );
            end else begin 
                partition_mem banks_01 (
                    .clk_i(clk_i)
                    ,.reset(reset)
                    ,.read_addr_i(bank_read_addr[i])
                    ,.write_addr_i(bank_write_addr[i])
                    ,.wren_i(bank_wren[i])
                    ,.write_data_i(bank_write_data[i])
                    ,.read_data_o(bank_read_data[i])
                );
            end

        end
    endgenerate

endmodule