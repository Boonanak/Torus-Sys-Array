module memory #(
     parameter memory_depth_p = 64
    ,parameter elements_per_vector_p = 8
    ,parameter weight_input_width_p = 8
    ,parameter psum_width_p = 16 // 16 or 32
    
    ,localparam addr_width_lp = $clog2(memory_depth_p)
    // Bank tag is 2 bits for 16-bit psum, 3 bits for 32-bit psum
    ,localparam bank_tag_width_lp = (psum_width_p == 16) ? 2 : 3
    ,localparam full_address_width_lp = addr_width_lp + bank_tag_width_lp

    ,localparam weight_input_vector_width_lp = elements_per_vector_p * weight_input_width_p
    ,localparam psum_vector_width_lp = elements_per_vector_p * psum_width_p
) (
     input logic clk_i
    ,input logic reset
    
    // Weight Port
    ,input logic weight_w_v_i
    ,input logic [addr_width_lp-1:0] weight_w_addr_i
    ,input logic [weight_input_vector_width_lp-1:0] weight_w_data_i
    ,input logic weight_r_v_i
    ,input logic [addr_width_lp-1:0] weight_r_addr_i
    ,output logic [weight_input_vector_width_lp-1:0] weight_r_data_o

    // Input Port
    ,input logic input_w_v_i
    ,input logic [addr_width_lp-1:0] input_w_addr_i
    ,input logic [weight_input_vector_width_lp-1:0] input_w_data_i
    ,input logic input_r_v_i
    ,input logic [addr_width_lp-1:0] input_r_addr_i
    ,output logic [weight_input_vector_width_lp-1:0] input_r_data_o

    // Psum Port
    ,input logic psum_w_v_i
    ,input logic [addr_width_lp-1:0] psum_w_addr_i
    ,input logic [psum_vector_width_lp-1:0] psum_w_data_i
    ,input logic psum_r_v_i
    ,input logic [addr_width_lp-1:0] psum_r_addr_i
    ,output logic [psum_vector_width_lp-1:0] psum_r_data_o

    // Chip IO Port
    ,input logic chip_io_w_v_i
    ,input logic [full_address_width_lp-1:0] chip_io_w_addr_i
    ,input logic [psum_vector_width_lp-1:0] chip_io_w_data_i
    ,input logic chip_io_r_v_i
    ,input logic [full_address_width_lp-1:0] chip_io_r_addr_i
    ,output logic [psum_vector_width_lp-1:0] chip_io_r_data_o
);

    // Internal Bank Signals
    logic weight_w_v, input_w_v, psum_w_v;
    logic weight_r_v, input_r_v, psum_r_v;
    logic [addr_width_lp-1:0] weight_w_addr, input_w_addr, psum_w_addr;
    logic [addr_width_lp-1:0] weight_r_addr, input_r_addr, psum_r_addr;
    logic [weight_input_vector_width_lp-1:0] weight_w_data, input_w_data;
    logic [psum_vector_width_lp-1:0] psum_w_data;
    
    // Internal Output Signals
    logic [weight_input_vector_width_lp-1:0] weight_r_data_int, input_r_data_int;
    logic [psum_vector_width_lp-1:0] psum_r_data_int;

    // Decode tags from chip_io
    logic [bank_tag_width_lp-1:0] w_tag, r_tag;
    assign w_tag = chip_io_w_addr_i[full_address_width_lp-1 : addr_width_lp];
    assign r_tag = chip_io_r_addr_i[full_address_width_lp-1 : addr_width_lp];

    // ---------------------------------------------------------
    // Bank 0: Weight Memory Logic
    // ---------------------------------------------------------
    always_comb begin 
        weight_w_v = weight_w_v_i;
        weight_w_addr = weight_w_addr_i;
        weight_w_data = weight_w_data_i;
        weight_r_v = weight_r_v_i;
        weight_r_addr = weight_r_addr_i;

        if (chip_io_w_v_i && (w_tag == 'd0)) begin 
            weight_w_v = 1'b1;
            weight_w_addr = chip_io_w_addr_i[addr_width_lp-1:0];
            weight_w_data = chip_io_w_data_i[weight_input_vector_width_lp-1:0];
        end
        if (chip_io_r_v_i && (r_tag == 'd0)) begin 
            weight_r_v = 1'b1;
            weight_r_addr = chip_io_r_addr_i[addr_width_lp-1:0];
        end
    end

    // ---------------------------------------------------------
    // Bank 1: Input Memory Logic
    // ---------------------------------------------------------
    always_comb begin 
        input_w_v = input_w_v_i;
        input_w_addr = input_w_addr_i;
        input_w_data = input_w_data_i;
        input_r_v = input_r_v_i;
        input_r_addr = input_r_addr_i;

        if (chip_io_w_v_i && (w_tag == 'd1)) begin 
            input_w_v = 1'b1;
            input_w_addr = chip_io_w_addr_i[addr_width_lp-1:0];
            input_w_data = chip_io_w_data_i[weight_input_vector_width_lp-1:0];
        end
        if (chip_io_r_v_i && (r_tag == 'd1)) begin 
            input_r_v = 1'b1;
            input_r_addr = chip_io_r_addr_i[addr_width_lp-1:0];
        end
    end

    // ---------------------------------------------------------
    // Bank 2+: Psum Memory Logic
    // Mapping: psum spans tags 2-3 (16-bit) or 2-5 (32-bit)
    // ---------------------------------------------------------
    always_comb begin 
        psum_w_v = psum_w_v_i;
        psum_w_addr = psum_w_addr_i;
        psum_w_data = psum_w_data_i;
        psum_r_v = psum_r_v_i;
        psum_r_addr = psum_r_addr_i;

        // Check if write tag falls within Psum range
        if (chip_io_w_v_i && (w_tag >= 'd2)) begin 
            psum_w_v = 1'b1;
            psum_w_addr = chip_io_w_addr_i[addr_width_lp-1:0]; 
            psum_w_data = chip_io_w_data_i;
        end
        
        if (chip_io_r_v_i && (r_tag >= 'd2)) begin 
            psum_r_v = 1'b1;
            psum_r_addr = chip_io_r_addr_i[addr_width_lp-1:0];
        end
    end

    // ---------------------------------------------------------
    // Output Multiplexing
    // ---------------------------------------------------------
    assign weight_r_data_o = weight_r_data_int;
    assign input_r_data_o  = input_r_data_int;
    assign psum_r_data_o   = psum_r_data_int;

    // Asynchronous Chip IO Read Mux
    always_comb begin
        case (r_tag)
            'd0:     chip_io_r_data_o = {{(psum_vector_width_lp-weight_input_vector_width_lp){1'b0}}, weight_r_data_int};
            'd1:     chip_io_r_data_o = {{(psum_vector_width_lp-weight_input_vector_width_lp){1'b0}}, input_r_data_int};
            default: chip_io_r_data_o = psum_r_data_int;
        endcase
    end

    /* // Logic for bsg_mem_1r1w_sync (1-cycle latency)
    // Requires a register to delay the read tag to align with the data output
    logic [bank_tag_width_lp-1:0] r_tag_delayed;
    always_ff @(posedge clk_i) begin
        if (reset) r_tag_delayed <= '0;
        else if (chip_io_r_v_i) r_tag_delayed <= r_tag;
    end

    always_comb begin
        case (r_tag_delayed)
            'd0:     chip_io_r_data_o = {{(psum_vector_width_lp-weight_input_vector_width_lp){1'b0}}, weight_r_data_int};
            'd1:     chip_io_r_data_o = {{(psum_vector_width_lp-weight_input_vector_width_lp){1'b0}}, input_r_data_int};
            default: chip_io_r_data_o = psum_r_data_int;
        endcase
    end
    */

    // ---------------------------------------------------------
    // Memory Instantiations
    // ---------------------------------------------------------
    bsg_mem_1r1w #(
         .width_p(weight_input_vector_width_lp) 
        ,.els_p(memory_depth_p)
    ) weight_memory (
         .w_clk_i(clk_i)
        ,.w_reset_i(reset)
        ,.w_v_i(weight_w_v)
        ,.w_addr_i(weight_w_addr)
        ,.w_data_i(weight_w_data)
        ,.r_v_i(weight_r_v)
        ,.r_addr_i(weight_r_addr)
        ,.r_data_o(weight_r_data_int)
    );

    bsg_mem_1r1w #(
         .width_p(weight_input_vector_width_lp) 
        ,.els_p(memory_depth_p)
    ) input_memory (
         .w_clk_i(clk_i)
        ,.w_reset_i(reset)
        ,.w_v_i(input_w_v)
        ,.w_addr_i(input_w_addr)
        ,.w_data_i(input_w_data)
        ,.r_v_i(input_r_v)
        ,.r_addr_i(input_r_addr)
        ,.r_data_o(input_r_data_int)
    );

    bsg_mem_1r1w #(
         .width_p(psum_vector_width_lp) 
        ,.els_p(memory_depth_p)
    ) psum_memory (
         .w_clk_i(clk_i)
        ,.w_reset_i(reset)
        ,.w_v_i(psum_w_v)
        ,.w_addr_i(psum_w_addr)
        ,.w_data_i(psum_w_data)
        ,.r_v_i(psum_r_v)
        ,.r_addr_i(psum_r_addr)
        ,.r_data_o(psum_r_data_int)
    );

endmodule