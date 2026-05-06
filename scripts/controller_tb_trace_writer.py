def generate_binary_trace(op, dest=0, src=0, acc=0, weight=0, vaddr=0, imm=0, header="0001"):
    """
    132-bit binary string (4b header + 128b ring data).
    Padding: 25 bits | Instr: 103 bits
    """
    h = header
    
    # Instruction Fields: 103 bits total (MSB to LSB)
    fields = [
        format(op,     '06b'), # op
        format(dest,   '06b'), # baddr_dest
        format(src,    '06b'), # baddr_src
        format(acc,    '06b'), # baddr_acc
        format(weight, '06b'), # baddr_weight
        format(vaddr,  '09b')  # vaddr
    ]
    
    # 64-bit immediate formatted in 8-bit chunks
    imm_bin = format(imm, '064b')
    imm_f = "_".join([imm_bin[i:i+8] for i in range(0, 64, 8)])
    
    pad = "0" * 25
    instr_f = "_".join(fields)
    
    return f"{h}_{pad}_{instr_f}_{imm_f}"

# --- Opcode Constants (Excluding CSR) ---
OP_READM8     = 0b001001
OP_WRITE      = 0b010000
OP_TRANSPOSE  = 0b011001
OP_CC         = 0b100100
OP_LC         = 0b110000
OP_LCCC       = 0b110100

# --- Sequence with DIM_p = 8, NUM_MATRICES = 4 ---
trace_sequence = [
    "# Trace 1: Write to Matrix 0, Row 0 (vaddr=0)",
    generate_binary_trace(OP_WRITE, vaddr=0, imm=0x0102030405060708),

    "# Trace 2: Write to Matrix 0, Row 1 (vaddr=1)",
    generate_binary_trace(OP_WRITE, vaddr=1, imm=0x1112131415161718),

    "# Trace 3: Write to Matrix 1, Row 0 (vaddr=8)",
    generate_binary_trace(OP_WRITE, vaddr=8, imm=0x2122232425262728),

    "# Trace 4: Write to Matrix 2, Row 0 (vaddr=16)",
    generate_binary_trace(OP_WRITE, vaddr=16, imm=0x3132333435363738),

    "# Trace 5: Load Matrix 1 into Weights (weight base 1)",
    generate_binary_trace(OP_LC, weight=1),

    "# Trace 6: Compute Matrix 0 * Matrix 1 -> Matrix 3",
    generate_binary_trace(OP_CC, dest=3, src=0, weight=1),

    "# Trace 7: Accumulate (Mat 0 * Mat 1) + Mat 2 -> Matrix 3",
    generate_binary_trace(OP_LCCC, dest=3, src=0, acc=2, weight=1),

    "# Trace 8: Transpose Result (Mat 3 -> Mat 0)",
    generate_binary_trace(OP_TRANSPOSE, dest=0, src=3),

    "# Trace 9: Read request for Matrix 0",
    generate_binary_trace(OP_READM8, src=0),

    "# Trace 10: Wait instruction (Header 0000)",
    "0000_" + "0"*25 + "_" + "_".join(["0"*6]*5) + "_" + "0"*9 + "_" + "_".join(["0"*8]*8),

    "# Trace 11: Finish Simulation (Header 0100)",
    "0100_" + "0"*25 + "_" + "_".join(["0"*6]*5) + "_" + "0"*9 + "_" + "_".join(["0"*8]*8)
]

# --- Write to File ---
file_name = "v/controller/controller_send_trace.tr"
with open(file_name, "w") as f:
    for line in trace_sequence:
        f.write(line + "\n")

print(f"Successfully wrote traces to {file_name}")