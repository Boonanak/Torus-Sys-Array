def to_bin(val, width):
    """Converts an integer to a binary string of a fixed width."""
    return format(val & ((1 << width) - 1), f'0{width}b')

def generate_32b_bin_flit(opcode, addr=0, baddr_dest=0, baddr_src=0, baddr_acc=0, baddr_weight=0):
    """
    Constructs a 32-bit binary flit based on ISA bit allocations. [cite: 31, 32, 34]
    Standard Addr (9b): Addr[31:23], Zero[22:6], Opcode[5:0] [cite: 24, 34]
    BaseAddr (6b each): Dest[31:26], Src[25:20], Acc[19:14], Weight[13:8], Zero[7:6], Opcode[5:0] [cite: 25, 34]
    """
    if addr != 0 or opcode in [8, 10, 16]: # Linear addressing opcodes [cite: 35, 37]
        return to_bin(addr, 9) + "0" * 17 + to_bin(opcode, 6)
    else:
        # Field order based on Instruction Breakdown [cite: 35, 37, 38, 39]
        return (to_bin(baddr_dest, 6) + to_bin(baddr_src, 6) + 
                to_bin(baddr_acc, 6) + to_bin(baddr_weight, 6) + 
                "00" + to_bin(opcode, 6))

trace_lines = []

NOOP = f'0000_{'0'*32}'
END  = f'0100_{'0'*32}'

# --- 1. Initialization ---
trace_lines.append("# NOOP Instruction")
trace_lines.append(NOOP) # [cite: 35]

# --- 2. 64-bit Memory Access (INT8 Vectors) ---
# Each row in the 64-bit memory holds eight 8-bit integers [cite: 43]
trace_lines.append("# WRITE Addr=0x01 (64-bit row)")
trace_lines.append(f'0001_{generate_32b_bin_flit(16, addr=1)}') # [cite: 35]
trace_lines.append("# Data Low")
trace_lines.append(f'0001_{to_bin(0x55667788, 32)}')
trace_lines.append("# Data High")
trace_lines.append(f'0001_{to_bin(0x11223344, 32)}')

trace_lines.append("# READV8 Addr=0x01")
trace_lines.append(f'0001_{generate_32b_bin_flit(8, addr=1)}') # [cite: 37]

# --- 3. 256-bit Memory Access (32-bit Elements) ---
# Updated architecture: 32-bit elements * 8 = 256-bit word line
trace_lines.append("# WRITE Addr=0x80 (256-bit row)")
trace_lines.append(f'0001_{generate_32b_bin_flit(16, addr=128)}')
for i in range(8):
    trace_lines.append(f"# Partial Sum Flit {i}")
    trace_lines.append(f'0001_{to_bin(0xAAAA0000 + i, 32)}')

# --- 4. Matrix Operations ---
# Load weights from Matrix 61 (Identity Matrix) 
trace_lines.append("# LR BaseAddr=61 (Load Identity Matrix weights)")
trace_lines.append(f'0001_{generate_32b_bin_flit(56, baddr_weight=61)}') # [cite: 37]

# Compute A * B + C [cite: 38]
trace_lines.append("# CR Dest=2, Src=0, Acc=62 (Compute using hard-coded Zero Matrix)")
trace_lines.append(f'0001_{generate_32b_bin_flit(38, baddr_dest=2, baddr_src=0, baddr_acc=62)}') # [cite: 38, 49]

# Simultaneous Load and Compute [cite: 39]
trace_lines.append("# LCCR Dest=3, Src=0, Weight=5, Acc=2")
trace_lines.append(f'0001_{generate_32b_bin_flit(54, baddr_dest=3, baddr_src=0, baddr_weight=5, baddr_acc=2)}') # [cite: 39]

# Transpose Matrix [cite: 35]
trace_lines.append("# TRANSPOSE Matrix 3 to Matrix 4")
trace_lines.append(f'0001_{generate_32b_bin_flit(25, baddr_dest=4, baddr_src=3)}') # [cite: 35]

# --- 5. Bulk Matrix Reads ---
trace_lines.append("# READM8 BaseAddr=4")
trace_lines.append(f'0001_{generate_32b_bin_flit(9, baddr_src=4)}') # [cite: 37]

# Reading Matrix 62 (Hard-coded Zero Matrix) 
trace_lines.append("# READM16 BaseAddr=62")
trace_lines.append(f'0001_{generate_32b_bin_flit(11, baddr_src=62)}') # [cite: 37]

# --- 6. Status and CSR ---
trace_lines.append("# ERROR CSR (Clear status flags)")
trace_lines.append(f'0001_{generate_32b_bin_flit(28)}') # [cite: 35]

trace_lines.append("# END SIMULATION")
trace_lines.append(END)

# --- Write to File ---
file_path = "v/Top_level/top_chip_send_trace.tr"
with open(file_path, "w") as f:
    for line in trace_lines:
        f.write(line + "\n")

print(f"Strict binary trace generated at: {file_path}")