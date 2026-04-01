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
            binary_str = f'0{'1'*(n_bits-1)}'
        return binary_str.zfill(n_bits)
    else:
        # For negative numbers, calculate two's complement
        # Range check: min value for n-bit signed int is -(2**(n-1))
        min_val = -(2**(n_bits - 1))
        max_val = (2**(n_bits - 1)) - 1
        if integer < min_val or integer > max_val:
            binary_str = f'1{'0'*(n_bits-1)}'
        else:
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

def matrix_trace_AB (AC, B, type, major):
    A_maj = 0
    B_maj = 0
    if major != None:
        A_maj = major[0] == 'R'
        B_maj = major[1] == 'R'
    if type == 'C':
        AC_binary_rows = matrix_to_binary_rows(AC, 16)
    elif AC is not None:
        AC_binary_rows = matrix_to_binary_rows(AC, 8)
    else:
        AC_binary_rows = {'0'*64}
    if B is not None:
        B_binary_rows = matrix_to_binary_rows(B, 8)
    trace_lines = ''
    match type:
        case 'A':
            trace_lines += f'# LOADING A into TPU | major = {major[0]}\n'
            for row, binary_row in zip(AC, AC_binary_rows):
                trace_lines += f'# A[i] = {row}\n'
                trace_lines += f'0001________{int(A_maj)}100_______{binary_row}________{'0'*32}\n'
        case 'B':
            trace_lines += f'# LOADING B into TPU | major = {major[1]}\n'
            for row, binary_row in zip(B, B_binary_rows):
                trace_lines += f'# B[i] = {row}\n'
                trace_lines += f'0001________00{int(B_maj)}1________{'0'*32}_______{binary_row}\n'
        case 'AB':
            #print(AC, B)
            trace_lines += f'# LOADING A and B into TPU | major = {major}\n'
            for rowA, binary_rowA, rowB, binary_rowB in zip(AC, AC_binary_rows, B, B_binary_rows):
                trace_lines += f'# A[i] = {rowA} B[i] = {rowB}\n'
                trace_lines += f'0001________{int(A_maj)}1{int(B_maj)}1_______{binary_rowA}_______{binary_rowB}\n'
        case 'C':
            trace_lines += '# RECEIVING C\n'
            for row, binary_row in zip(AC, AC_binary_rows):
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
            min_val = -(2**(size - 1))
            max_val = (2**(size - 1)) - 1
            if n < min_val:
                binary_repr = f'1{'0'*(size-1)}'
            elif n > max_val:
                binary_repr = f'0{'1'*(size-1)}'
            else:
                binary_repr = np.binary_repr(int(n), width=size)
            binary_row += f'_{binary_repr}'
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

def write_trace_sysarray(tests, trace_send, trace_recv):
    with open(trace_send, 'w') as trace_send, open(trace_recv, 'w') as trace_recv:
        #trace_recv.write({"# NOOP\n0000__{'0'*64}\n"}*0)
        for test in tests:
            if test[0] != None:
                #print(test[0])
                trace_send.write(matrix_trace_AB(test[0][0], test[0][1], test[0][2], test[0][3]))
            else:
                trace_send.write(matrix_trace_AB(None, None, 'N', None))
            if test[1] is not None:
                trace_recv.write(matrix_trace_AB(test[1], None, 'C', None))
            else:
                trace_recv.write(matrix_trace_AB(None, None, 'N', None))
        #trace_send.write({f"# NOOP\n0000__{'0'*64}\n"}*0)
        trace_send.write(f"# ENDING SIMULATION\n0100__{'0'*64}\n")
        trace_recv.write(f"# ENDING SIMULATION\n0100__{'0'*64}\n")
    return


### Matrix writing and trace files
import random
import numpy as np

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
A1 = np.identity(4)
A2 = np.array([[1, 2, 3, 4], [2, 3, 4, 3], [3, 4, 3, 2], [4, 3, 2, 1]])
A3 = -A2
A4 = np.full((4,4), 127)
A5 = -A4
A6 = np.array([[117, -49, -115, -92], [-63, -122, -64, -32], [-128, 91, 41, -27], [29, 122, -31, 53]])
A7 = np.array([[-12, 33, -83, -80], [29, -67, -52, -7], [75, 38, 27, 120], [-126, 31, 66, -121]])
B1 = np.identity(4)
B2 = np.arange(1, 17).reshape(4,4)
B3 = A4
B4 = B2.T
B5 = np.array([[109, -5, 55, 41], [3, -26, -60, -124], [-64, -48, 80, -109], [-116, 73, 41, 78]])
B6 = np.array([[30, 36, 53, -17], [-81, 78, 122, 18], [50, -121, -117, -49], [-104, 40, -91, -28]])
# C11 = multiply(A1, B1) # identity * identity
# C21 = multiply(A2, B1) #  A * identity
# C31 = multiply(A3, B1) # -A * identity
# C12 = multiply(A1, B2) # identity * B --> same result with B4
# C22 = multiply(A2, B2) #  A * B       --> same result with B4
# C32 = multiply(A3, B2) # -A * B       --> same result with B4
# C43 = multiply(A4, B3) # positive overflow
# C53 = multiply(A5, B3) # negative overflow
# C65 = multiply(A6, B5) # random 1
# C76 = multiply(A7, B6) # random 2
# tests = [
#     [[B1, 'B', 'row'], None],
#     [[A1, 'A', 'row'], None],
#     [[A2, 'A', 'row'], None],
#     [[A3, 'A', 'row'], [C11, 'C', None]],
#     [[B2, 'B', 'row'], [C21, 'C', None]],
#     [[A1, 'A', 'row'], [C31, 'C', None]],
#     [[A2, 'A', 'row'], None],
#     [[A3, 'A', 'row'], [C12, 'C', None]],
#     [[B3, 'B', 'row'], [C22, 'C', None]],
#     [[A4, 'A', 'row'], [C32, 'C', None]],
#     [[B1, 'B', 'col'], None],
#     [[A1, 'A', 'col'], [C43, 'C', None]],
#     [[A2, 'A', 'col'], None],
#     [[A3, 'A', 'col'], [C11, 'C', None]],
#     [[B2, 'B', 'col'], [C21, 'C', None]],
#     [[A1, 'A', 'col'], [C31, 'C', None]],
#     [[A2, 'A', 'col'], None],
#     [[A3, 'A', 'col'], [C12, 'C', None]],
#     [[B4, 'B', 'col'], [C22, 'C', None]],
#     [[A5, 'A', 'col'], [C32, 'C', None]],
#     [None, None],
#     [None, [C53, 'C', None]],
#     [None, None],
#     [[B5, 'B', 'row'], None],
#     [[A6, 'A', 'row'], None],
#     [[B6, 'B', 'row'], None],
#     [[A7, 'A', 'row'], [C65, 'C', None]],
#     [None, None],
#     [None, [C65, 'C', None]]
# ]


tests_AB = [
    [[None, B1, 'B', 'XR'], None], # transpose of identity is identity
    [[A1, None, 'A', 'RX'], A1 @ B1], # A1-3 @ B1
    [[A2, None, 'A', 'RX'], A2 @ B1],
    [[A3, B4, 'AB', 'RR'], A3 @ B1], # transpose of B2 is B4
    [[A1, None, 'A', 'RX'], A1 @ B2], # A1-3 @ B2
    [[A2, None, 'A', 'RX'], A2 @ B2],
    [[A3, B3, 'AB', 'RR'], A3 @ B2], # transpose of B3 is B3
    [[A4, None, 'A', 'RX'], A4 @ B3], # positive overflow
    [[A5, B5, 'AB', 'RR'], A5 @ B3],
    [[A6, B6, 'AB', 'RR'], A6 @ B5],
    [[A7, None, 'A', 'RX'], A7 @ B6]
]

# tests = [
#     [[B2, 'B', 'row'], None],
#     [[A1, 'A', 'row'], None],
#     [None, None],
#     [None, [C12, 'C', None]]
# ]

write_trace_sysarray(tests_AB, 'v/TEMPsys_array_send_trace.tr', 'v/TEMPsys_array_recv_trace.tr')

