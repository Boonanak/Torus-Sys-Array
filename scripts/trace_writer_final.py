# Code to generate trace files for top level module

#######################################################################################################
#
# format:   <4 bit op> <fsb packet>
#   op = 0000: wait one cycle
#   op = 0001: send
#   op = 0010: receive & check
#   op = 0011: done; disable but do not stop
#   op = 0100: finish; stop simulation
#   op = 0101: wait for cycle ctr to reach 0
#   op = 0110: set cycle ctr
#
# fsb packet (data)
# 1 bit    75 bits
#   0       data
#
# fsb packet (control)
# 1 bit    7 bits    4 bits   64 bits
#   1      opcode    srcid    data
#
# opcodes
#   1: 0000_001 = disable
#   2: 0000_010 = enable
#   5: 0000_101 = assert reset
#   6: 0000_110 = deassert reset
#

def to_signed_nbit_binary(integer, n_bits):
    """
    Converts an integer to a signed N-bit binary string (two's complement).
    """
    if integer >= 0:
        # For positive numbers, use standard format and pad with zeros
        binary_str = format(integer, 'b')
        if len(binary_str) > n_bits:
            raise ValueError(f"Positive integer {integer} out of range for {n_bits} bits")
        return binary_str.zfill(n_bits)
    else:
        # For negative numbers, calculate two's complement
        # Range check: min value for n-bit signed int is -(2**(n-1))
        min_val = -(2**(n_bits - 1))
        max_val = (2**(n_bits - 1)) - 1
        if integer < min_val or integer > max_val:
            raise ValueError(f"Negative integer {integer} out of range for {n_bits} bits (range: {min_val} to {max_val})")

        # Calculate two's complement
        # Formula: (2**n_bits) + integer
        twos_complement_val = (1 << n_bits) + integer 
        binary_str = format(twos_complement_val, 'b')
        
        # This should always be n_bits long if the input is in range, but zfill ensures it
        return binary_str.zfill(n_bits)

def matrix_trace(M, type, major):
    if type == 'C':
        n = 16
    else:
        n = 8
    if M != None:
        M_binary_rows = matrix_to_binary_rows(M, n)
    row_major = major == 'row'
    trace_lines = ''
    match type:
        case 'A':
            trace_lines += f'# LOADING A into TPU | major = {major} | loadB = 0\n'
            for row, binary_row in zip(M, M_binary_rows):
                trace_lines += f'# A[i] = {row}\n'
                trace_lines += f'0001________{int(row_major)}______0______{'0'*30}_______{binary_row}\n'
        case 'B':
            trace_lines += f'# LOADING B into TPU | major = {major} | loadB = 1\n'
            for row, binary_row in zip(M, M_binary_rows):
                trace_lines += f'# B[i] = {row}\n'
                trace_lines += f'0001________{int(row_major)}______1______{'0'*30}_______{binary_row}\n'
        case 'C':
            trace_lines += '# RECEIVING C\n'
            for row, binary_row in zip(M, M_binary_rows):
                trace_lines += f'# C[i] = {row}\n'
                trace_lines += f'0010________{binary_row}\n'
        case 'N':
            trace_lines += f"# NOOP\n{f'0000__{'0'*64}\n'*4}"
    return trace_lines + '\n'

def multiply_trace(A, B, C, op, major):
    A_binary_rows = matrix_to_binary_rows(A, 8)
    B_binary_rows = matrix_to_binary_rows(B, 8)
    C_binary_rows = matrix_to_binary_rows(C, 16)
    row_major = major == 'row'
    trace_lines_send = ''
    trace_lines_recv = ''
    SEND_NOOP = f"# NOOP for SEND\n{f'0000__{'0'*64}\n'*4}"
    RECV_NOOP = f"# NOOP for RECV\n{f'0000__{'0'*64}\n'*4}"
    match op:
        case 'loadA':
            trace_lines_send += f'# LOADING A into TPU | major = {major} | loadB = 0\n'
            for row, binary_row in zip(A, A_binary_rows):
                trace_lines_send += f'# A[i] = {row}\n'
                trace_lines_send += f'0001________{int(row_major)}______0______{'0'*30}_______{binary_row}\n'
            trace_lines_recv += RECV_NOOP
        case 'loadB':
            trace_lines_send += f'# LOADING B into TPU | major = {major} | loadB = 1\n'
            for row, binary_row in zip(B, B_binary_rows):
                trace_lines_send += f'# B[i] = {row}\n'
                trace_lines_send += f'0001________{int(row_major)}______1______{'0'*30}_______{binary_row}\n'
            trace_lines_recv += RECV_NOOP
        case 'recvC':
            trace_lines_send += SEND_NOOP
            trace_lines_recv += '# RECEIVING C'
            for row, binary_row in zip(C, C_binary_rows):
                trace_lines_recv += f'# C[i] = {row}\n'
                trace_lines_recv += f'0010________{binary_row}'
        case 'loadA_recvC':
            trace_lines_send += f'# LOADING A into TPU | major = {major} | loadB = 0\n'
            for row, binary_row in zip(A, A_binary_rows):
                trace_lines_send += f'# A[i] = {row}\n'
                trace_lines_send += f'0001________{int(row_major)}______0______{'0'*30}_______{binary_row}\n'
            trace_lines_recv += '# RECEIVING C'
            for row, binary_row in zip(C, C_binary_rows):
                trace_lines_recv += f'# C[i] = {row}\n'
                trace_lines_recv += f'0010________{binary_row}\n'
        case 'loadB_recvC':
            trace_lines_send += f'# LOADING B into TPU | major = {major} | loadB = 1\n'
            for row, binary_row in zip(B, B_binary_rows):
                trace_lines_send += f'# B[i] = {row}\n'
                trace_lines_send += f'0001________{int(row_major)}______1______{'0'*30}_______{binary_row}\n'
            trace_lines_recv += '# RECEIVING C'
            for row, binary_row in zip(C, C_binary_rows):
                trace_lines_recv += f'# C[i] = {row}\n'
                trace_lines_recv += f'0010________{binary_row}\n'
        case 'loadA-recvC':
            # loadA followed by receive C (both in parallel with NOOPs)
            trace_lines_send += f'# LOADING A into TPU | major = {major} | loadB = 0\n'
            for row, binary_row in zip(A, A_binary_rows):
                trace_lines_send += f'# A[i] = {row}\n'
                trace_lines_send += f'0001________{int(row_major)}______0______{'0'*30}_______{binary_row}\n'
            trace_lines_recv += RECV_NOOP
            trace_lines_send += SEND_NOOP
            trace_lines_recv += '# RECEIVING C'
            for row, binary_row in zip(C, C_binary_rows):
                trace_lines_recv += f'# C[i] = {row}\n'
                trace_lines_recv += f'0010________{binary_row}'
        case 'loadA-loadB_recvC': 
            # full throughput case, loads next B while receiving C (cannot receive new C until new A has been loaded)
            # load A in parallel with NOOP, loadB in parallel with receive C
            trace_lines_send += ''
            trace_lines_recv += ''
        case 'loadA-loadA_recvC': 
            # full throughput case, uses B as next A
            # load B in parallel with **nothing** (so that it can be a noop OR receiving a C), loadA in parallel with receive C
            trace_lines_send += ''
            trace_lines_recv += ''
        case 'loadB-loadA-recvC':
            # loadB, followed by loadA, followed by receive C, all NOOPs in parallel
            trace_lines_send += ''
            trace_lines_recv += ''
        case 'sendNOOP':
            trace_lines_send += SEND_NOOP
        case 'recvNOOP':
            trace_lines_recv += RECV_NOOP
    return trace_lines_send + '\n', trace_lines_recv + '\n'

def matrix_to_binary_rows(M, size):
    binary_rows = []
    for row in M:
        binary_row = ''
        for n in row:
            binary_row += f'_{to_signed_nbit_binary(n, size)}'
        binary_rows.append(binary_row)
    return binary_rows

def write_trace_final(tests, trace_send, trace_recv):
    with open(trace_send, 'w') as trace_send, open(trace_recv, 'w') as trace_recv:
        #trace_recv.write(f"# NOOP\n0000__{'0'*64}\n")
        for test in tests:
            if test[0] != None:
                trace_send.write(matrix_trace(test[0][0], test[0][1], test[0][2]))
            else:
                trace_send.write(matrix_trace(None, 'N', None))
            if test[1] != None:
                trace_recv.write(matrix_trace(test[1][0], test[1][1], test[1][2]))
            else:
                trace_recv.write(matrix_trace(None, 'N', None))
        #trace_send.write(f"# NOOP\n0000__{'0'*64}\n")
        trace_send.write(f"# ENDING SIMULATION\n0100__{'0'*64}\n")
        trace_recv.write(f"# ENDING SIMULATION\n0100__{'0'*64}\n")
    return


### Matrix writing and trace files
import random

# Generate Random Matrix
def gen_matrix(N, min_val, max_val):
    return [[random.randint(min_val, max_val) for _ in range(N)] for _ in range(N)]

def multiply(A, B):
    N = len(A)
    C = [[0]*N for _ in range(N)]
    for i in range(N):
        for j in range(N):
            for k in range(N):
                C[i][j] += A[i][k] * B[k][j]
    return C

def print_matrix(M):
    for row in M:
        print([f"{v:4d}" for v in row])

# Example: 4x4, int8 range
n = 4  # Number of rows and columns in the matrix.
identity = [[0] * i + [1] + [0] * (n - i - 1) for i in range(n)]
A1 = identity
B1 = identity
#B1 = gen_matrix(4, -128, 127)
C11 = multiply(A1, B1)
A2 = [[1, 2, 3, 4], [2, 3, 4, 3], [3, 4, 3, 2], [4, 3, 2, 1]]
C21 = multiply(A2, B1)
B2 = [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12], [13, 14, 15, 16]]
C12 = multiply(A1, B2)
C22 = multiply(A2, B2)
# tests = [
#     [[B1, 'B', 'row'], None],
#     [[A1, 'A', 'row'], None],
#     [[A2, 'A', 'row'], [C11, 'C', None]],
#     [[B2, 'B', 'row'], [C21, 'C', None]],
#     [[A1, 'A', 'row'], None],
#     [[A2, 'A', 'row'], [C12, 'C', None]],
#     [None, [C22, 'C', None]]
# ]
tests = [
    [[B2, 'B', 'row'], None],
    [[A1, 'A', 'row'], None],
    [None, None],
    [None, [C12, 'C', None]]
]

write_trace_final(tests, 'v/Top_level/Top_level_send_trace.tr', 'v/Top_level/Top_level_recv_trace.tr')

