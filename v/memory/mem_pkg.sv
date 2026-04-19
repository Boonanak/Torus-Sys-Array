package mem_pkg;

    parameter DATA_WIDTH = 128;
    parameter ADDR_LENGTH = 9;

    typedef struct packed {
        logic [2:0] block_idx;
        logic [1:0] bank;
        logic [2:0] wl_offset;
        logic       seg_sel;
    } banked_mem_fields;

    typedef union packed {
        logic [ADDR_LENGTH - 1 : 0] raw;
        banked_mem_fields fields;
    } mem_addr;

    typedef struct packed {
        mem_addr addr;
        logic valid;
    } r_req;

    typedef struct packed {
        logic [DATA_WIDTH - 1 : 0] data;
        logic valid;
    } r_rsp;

    typedef struct packed {
        mem_addr addr;
        logic [1:0] wren; // TODO: remove magic number
        logic valid;
        logic [DATA_WIDTH - 1 : 0] data;
    } w_req;

    typedef struct packed {
        logic valid;
    } w_rsp;

endpackage