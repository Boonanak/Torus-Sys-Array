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

import numpy as np

AB_WIDTH = 8
C_WIDTH = 16
MATRIX_SIZE = 8
DELAY = 9

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
        fill = 8*len(M) - 2
    row_major = major == 'row'
    trace_lines = ''
    match type:
        case 'A':
            trace_lines += f'# LOADING A into TPU | major = {major} | loadB = 0\n'
            for row, binary_row in zip(M, M_binary_rows):
                trace_lines += f'# A[i] = {row}\n'
                trace_lines += f'0001________{int(row_major)}______0______{'0'*fill}_______{binary_row}\n'
        case 'B':
            trace_lines += f'# LOADING B into TPU | major = {major} | loadB = 1\n'
            for row, binary_row in zip(M, M_binary_rows):
                trace_lines += f'# B[i] = {row}\n'
                trace_lines += f'0001________{int(row_major)}______1______{'0'*fill}_______{binary_row}\n'
        case 'C':
            trace_lines += '# RECEIVING C\n'
            for row, binary_row in zip(M, M_binary_rows):
                trace_lines += f'# C[i] = {row}\n'
                trace_lines += f'0010________{binary_row}\n'
        case 'N':
            trace_lines += f"# NOOP\n{f'0000__{'0'*64}\n'*4}"
    return trace_lines + '\n'

# Converts a matrix M to a series of {size}-bit binary numbers separated by underscores; returns a string
def matrix_to_binary_rows(M, size):
    binary_rows = []
    for row in M:
        binary_row = ''
        for n in row:
            binary_row += f'_{to_signed_nbit_binary(int(n), size)}'
        binary_rows.append(binary_row)
    return binary_rows

def write_trace_final(tests, trace_send, trace_recv):
    with open(trace_send, 'w') as trace_send, open(trace_recv, 'w') as trace_recv:
        trace_recv.write(f"# NOOP\n0000__{'0'*64}\n")
        for test in tests:
            if test[0] != None:
                trace_send.write(matrix_trace(test[0][0], test[0][1], test[0][2]))
            else:
                trace_send.write(matrix_trace(None, 'N', None))
            if test[1] != None:
                trace_recv.write(matrix_trace(test[1][0], test[1][1], test[1][2]))
            else:
                trace_recv.write(matrix_trace(None, 'N', None))
        trace_send.write(f"# NOOP\n0000__{'0'*64}\n")
        trace_send.write(f"# ENDING SIMULATION\n0100__{'0'*64}\n")
        trace_recv.write(f"# ENDING SIMULATION\n0100__{'0'*64}\n")
    return

def TwistMesh_trace(op, A = None, B = None, C = None):
    trace_lines = ''
    if A is not None:
        A_binary_rows = matrix_to_binary_rows(A, AB_WIDTH)
    else:
        A_binary_rows = matrix_to_binary_rows(np.zeros((MATRIX_SIZE, MATRIX_SIZE)), AB_WIDTH)
    if B is not None:
        B_binary_rows = matrix_to_binary_rows(B, AB_WIDTH)
    else:
        B_binary_rows = matrix_to_binary_rows(np.zeros((MATRIX_SIZE, MATRIX_SIZE)), AB_WIDTH)
    if C is not None:
        C_binary_rows = matrix_to_binary_rows(C, C_WIDTH)
    else:
        C_binary_rows = matrix_to_binary_rows(np.zeros((MATRIX_SIZE, MATRIX_SIZE)), C_WIDTH)
    ZERO_AB = f'{f'_{'0'*AB_WIDTH}'*MATRIX_SIZE}'
    ZERO_C = f'{f'_{'0'*C_WIDTH}'*MATRIX_SIZE}'
    match op:
        case 'load':
            trace_lines += f'# LOADING B into systolic array\n'
            for i in range(len(B)):
                lock_sig = f'{'0'*MATRIX_SIZE}'
                lock_sig = lock_sig[:i] + '1' + lock_sig[i+1:]
                propagate = 0
                trace_lines += f'# B[{i}] = {B[i]} | lock_sig = {lock_sig} | propagate = 1\n'
                trace_lines += f'0001________{propagate}_{lock_sig}___{A_binary_rows[i]}___{B_binary_rows[i]}___{C_binary_rows[i]}\n'
        case 'compute':
            trace_lines += f'# COMPUTING A * B + C\n'
            for i in range(len(A)):
                lock_sig = f'{'0'*MATRIX_SIZE}'
                propagate = 1
                trace_lines += f'# A[{i}] = {A[i]} | C[{i}] = {C[i] if C is not None else '0'} | propagate = 0\n'
                trace_lines += f'0001________{propagate}_{lock_sig}___{A_binary_rows[i]}___{B_binary_rows[i]}___{C_binary_rows[i]}\n'
        case 'load_compute':
            trace_lines += f'# COMPUTING A * B + C, LOADING new B\n'
            for i in range(len(B)):
                lock_sig = f'{'0'*MATRIX_SIZE}'
                lock_sig = lock_sig[:i] + '1' + lock_sig[i+1:]
                propagate = 1
                trace_lines += f'# A[{i}] = {A[i]} | B[{i}] = {B[i]} | C[{i}] = {C[i] if C is not None else '0'} | lock_sig = {lock_sig} | propagate = 1\n'
                trace_lines += f'0001________{propagate}_{lock_sig}___{A_binary_rows[i]}___{B_binary_rows[i]}___{C_binary_rows[i]}\n'
        case 'recv':
            trace_lines += f'# RECEIVING C\n'
            for i in range(len(C)):
                trace_lines += f'# C[{i}] = {C[i]}\n'
                trace_lines += f'0010_______{C_binary_rows[i]}\n'
        case 'send_noop':
            trace_lines += f'# NOOP\n0000________0_{'0'*MATRIX_SIZE}___{ZERO_AB}___{ZERO_AB}___{ZERO_C}\n'
        case 'recv_noop':
            trace_lines += f'# NOOP\n0000_______{ZERO_C}\n'
        case 'send_end':
            trace_lines += f'# ENDING SIMULATION\n0100________0_{'0'*MATRIX_SIZE}___{ZERO_AB}___{ZERO_AB}___{ZERO_C}\n'
        case 'recv_end':
            trace_lines += f'# ENDING SIMULATION\n0100_______{ZERO_C}\n'
    return trace_lines




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

def transpose(M):
    M_T = [[M[j][i] for j in range(len(M[0]))] for i in range(len(M))]
    return M_T

# Example: 4x4, int8 range
n = 4  # Number of rows and columns in the matrix.
identity = [[0] * i + [1] + [0] * (n - i - 1) for i in range(n)]
A1 = identity
A2 = [[1, 2, 3, 4], [2, 3, 4, 3], [3, 4, 3, 2], [4, 3, 2, 1]]
A3 = -1*A2
A4 = [[127]*n for i in range(n)]
A5 = -1*A4
A6 = [[117, -49, -115, -92], [-63, -122, -64, -32], [-128, 91, 41, -27], [29, 122, -31, 53]]
A7 = [[-12, 33, -83, -80], [29, -67, -52, -7], [75, 38, 27, 120], [-126, 31, 66, -121]]
B1 = identity
B2 = [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12], [13, 14, 15, 16]]
B3 = A4
B4 = transpose(B2)
B5 = [[109, -5, 55, 41], [3, -26, -60, -124], [-64, -48, 80, -109], [-116, 73, 41, 78]]
B6 = [[30, 36, 53, -17], [-81, 78, 122, 18], [50, -121, -117, -49], [-104, 40, -91, -28]]
#B1 = gen_matrix(4, -128, 127)
C11 = multiply(A1, B1) # identity * identity
C21 = multiply(A2, B1) #  A * identity
C31 = multiply(A3, B1) # -A * identity
C12 = multiply(A1, B2) # identity * B --> same result with B4
C22 = multiply(A2, B2) #  A * B       --> same result with B4
C32 = multiply(A3, B2) # -A * B       --> same result with B4
C43 = multiply(A4, B3) # positive overflow
C53 = multiply(A5, B3) # negative overflow
C65 = multiply(A6, B5) # random 1
C76 = multiply(A7, B6) # random 2
tests = [
    [[B1, 'B', 'row'], None],
    [[A1, 'A', 'row'], None],
    [[A2, 'A', 'row'], None],
    [[A3, 'A', 'row'], [C11, 'C', None]],
    [[B2, 'B', 'row'], [C21, 'C', None]],
    [[A1, 'A', 'row'], [C31, 'C', None]],
    [[A2, 'A', 'row'], None],
    [[A3, 'A', 'row'], [C12, 'C', None]],
    [[B3, 'B', 'row'], [C22, 'C', None]],
    [[A4, 'A', 'row'], [C32, 'C', None]],
    [[B1, 'B', 'col'], None],
    [[A1, 'A', 'col'], [C43, 'C', None]],
    [[A2, 'A', 'col'], None],
    [[A3, 'A', 'col'], [C11, 'C', None]],
    [[B2, 'B', 'col'], [C21, 'C', None]],
    [[A1, 'A', 'col'], [C31, 'C', None]],
    [[A2, 'A', 'col'], None],
    [[A3, 'A', 'col'], [C12, 'C', None]],
    [[B4, 'B', 'col'], [C22, 'C', None]],
    [[A5, 'A', 'col'], [C32, 'C', None]],
    [None, None],
    [None, [C53, 'C', None]],
    [None, None],
    [[B5, 'B', 'row'], None],
    [[A6, 'A', 'row'], None],
    [[B6, 'B', 'row'], None],
    [[A7, 'A', 'row'], [C65, 'C', None]],
    [None, None],
    [None, [C65, 'C', None]]
]
# tests = [
#     [[B2, 'B', 'row'], None],
#     [[A1, 'A', 'row'], None],
#     [None, None],
#     [None, [C12, 'C', None]]
# ]

#write_trace_final(tests, 'v/Top_level/Top_level_send_trace.tr', 'v/Top_level/Top_level_recv_trace.tr')
I = np.identity(8)
Z = np.zeros((8,8))
inc_0_63 = np.arange(0,MATRIX_SIZE**2).reshape(MATRIX_SIZE, MATRIX_SIZE)
inc_0_63_neg = inc_0_63 * -1
inc_0_63_T = inc_0_63.T
inc_0_63_squared = inc_0_63 @ inc_0_63
inc_0_63_squared_neg = inc_0_63_squared * -1


TwistMesh = [
    [['load', None, I, None], None],
    [['compute', I, None, None], ['recv', None, None, I]],
    [['compute', inc_0_63, None, None], ['recv', None, None, inc_0_63]],
    [['load_compute', inc_0_63_neg, inc_0_63, Z], ['recv', None, None, inc_0_63_neg]],
    [['compute', I, None, None], ['recv', None, None, inc_0_63]],
    [['compute', inc_0_63, None, None], ['recv', None, None, inc_0_63_squared]],
    [['compute', inc_0_63_neg, None, None], ['recv', None, None, inc_0_63_squared_neg]]
]

with open('v/sys_array/TwistMesh_send_trace.tr', 'w') as trace_send, open('v/sys_array/TwistMesh_recv_trace.tr', 'w') as trace_recv:
    trace_recv.write(TwistMesh_trace('recv_noop')*DELAY)
    for instruction in TwistMesh:
        
        if instruction[0] != None:
            trace_send.write(TwistMesh_trace(instruction[0][0], instruction[0][1], instruction[0][2], instruction[0][3]))
        else:
            trace_send.write(TwistMesh_trace('send_noop')*MATRIX_SIZE)
        if instruction[1] != None:
            trace_recv.write(TwistMesh_trace(instruction[1][0], instruction[1][1], instruction[1][2], instruction[1][3]))
        else:
            trace_recv.write(TwistMesh_trace('recv_noop')*MATRIX_SIZE)
    trace_send.write(TwistMesh_trace('send_noop')*DELAY)
    trace_send.write(TwistMesh_trace('send_end'))
    trace_recv.write(TwistMesh_trace('recv_end'))
TwistMesh_trace('load', None, np.identity(8), None)
TwistMesh_trace('compute', np.arange(0,MATRIX_SIZE**2).reshape(MATRIX_SIZE, MATRIX_SIZE), None, None)
TwistMesh_trace('recv', None, None, np.identity(8))

