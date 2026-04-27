
package ctrl_pkg;

    typedef enum logic [5:0] {
        OP_NOOP      = 6'b000000,
        OP_READV8    = 6'b001000,
        OP_READM8    = 6'b001001,
        OP_READV16   = 6'b001010,
        OP_READM16   = 6'b001011,
        OP_READ_CSR  = 6'b001100,
        OP_WRITE     = 6'b010000,
        OP_WRITE_CSR = 6'b010100,
        OP_TRANSPOSE = 6'b011001,
        OP_ERROR_CSR = 6'b011100,
        OP_CC        = 6'b100100,
        OP_CR        = 6'b100110,
        OP_LC        = 6'b110000,
        OP_LCCC      = 6'b110100,
        OP_LCCR      = 6'b110110,
        OP_LR        = 6'b111000,
        OP_LRCC      = 6'b111100,
        OP_LRCR      = 6'b111110
    } opcode_e;

    typedef struct packed {
        opcode_e     op;
        logic [5:0]  baddr_dest;  // CR/CC/LxCx/TRANSPOSE dest
        logic [5:0]  baddr_src;  // CR/CC/LxCx/TRANSPOSE source A / READM source
        logic [5:0]  baddr_acc;  // CR/CC/LxCx bias C
        logic [5:0]  baddr_weight;  // LR/LC/LxCx weight
        logic [8:0]  vaddr;  // READV/WRITE 9-bit vector addr
        logic [63:0] imm_data;  // WRITE / WRITE_CSR payload
    } decoded_cmd_t;

    typedef struct packed {
        logic        do_compute;  // drive A/bias; capture out_psum
        logic        do_load_weight;  // drive weight/lock
        logic        flip_propagate;  // XOR prop_r on accept (=1 when loading weight)
        logic [5:0]  src_a_base;  // A operand matrix
        logic [5:0]  src_bias_base;  // C bias matrix
        logic [5:0]  src_wgt_base;  // B weight matrix
        logic [5:0]  dst_base;  // output matrix
        logic        a_transpose;  // route A through transposer
        logic        d_transpose;  // route D (weight) through transposer
    } mesh_req_t;

    typedef struct packed {
        logic overflow;  // mesh saturation
        logic write_rom;  // wrote to ROM address
        logic invalid_op;  // decoder unknown opcode
        logic mem_conflict;  // arbiter denied access (should not happen in v1)
        logic transpose_conflict;  // exec needs two transposes simultaneously
        logic parity_fail;  // input parity mismatch
    } err_pulse_t;

    parameter int CSR_BIT_PARITY_OK         = 0;
    parameter int CSR_BIT_OVERFLOW          = 1;
    parameter int CSR_BIT_WRITE_ROM         = 2;
    parameter int CSR_BIT_INVALID_OP        = 3;
    parameter int CSR_BIT_MEM_CONFLICT      = 4;
    parameter int CSR_BIT_TRANSPOSE_CONFLICT= 5;
    parameter int CSR_BIT_ERROR_ANY         = 6;  // OR of bits 1..5

    parameter int CSR_ERR_MASK = (1 << CSR_BIT_OVERFLOW)
                               | (1 << CSR_BIT_WRITE_ROM)
                               | (1 << CSR_BIT_INVALID_OP)
                               | (1 << CSR_BIT_MEM_CONFLICT)
                               | (1 << CSR_BIT_TRANSPOSE_CONFLICT)
                               | (1 << CSR_BIT_ERROR_ANY);

    parameter int FLIT_W_p    = 32;  // ISA flit
    parameter int LINK_W_p    = 16;  // BSG link flit (info only)

endpackage
