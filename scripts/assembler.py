# Code to convert from TPU instructions to machine code (TPU)

#######################################################################################################
#
# format:   <5 bit opcode> <75 bits instruction data>
#   
#
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

# Possible instructions:
# 000000 =  0: NOOP
# 010000 = 16: WRITE8 <Addr> [<data1>, <data2>, ...]
# 010010 = 18: WRITE32 <Addr> [<data1>, <data2>, ...]
# 011001 = 25: TRANSPOSE <BaseAddr_dest> <BaseAddr_source>
# 010100 = 20: WRITE_CSR
# 011100 = 28: ERROR_CSR
# 001100 = 12: READ_CSR
# 001001 =  9: READM8 <BaseAddr>
# 001011 = 11: READM16 <BaseAddr>
# 001000 =  8: READV8 <Addr>
# 001010 = 10: READV16 <Addr>
# 111000 = 56: LR <BaseAddr_weight>
# 110000 = 48: LC <BaseAddr_weight>
# 100110 = 38: CR <BaseAddr_dest> <BaseAddr_source>
# 100100 = 36: CC <BaseAddr_dest> <BaseAddr_source>
# 100111 = 39: CRA <BaseAddr_dest> <BaseAddr_source> <BaseAddr_acc>
# 100101 = 37: CCA <BaseAddr_dest> <BaseAddr_source> <BaseAddr_acc>
# 111110 = 62: LRCR <BaseAddr_dest> <BaseAddr_source> <BaseAddr_weight>
# 110110 = 54: LCCR <BaseAddr_dest> <BaseAddr_source> <BaseAddr_weight>
# 111100 = 60: LRCC <BaseAddr_dest> <BaseAddr_source> <BaseAddr_weight>
# 110100 = 52: LCCC <BaseAddr_dest> <BaseAddr_source> <BaseAddr_weight>

import math
DIM           = 8
AB_WIDTH      = 8
C_WIDTH       = 32
FLIT_WIDTH    = 32
AB_MEM_DEPTH  = 64
C_MEM_DEPTH   = 32
AB_ADDR_W     = int(math.log2(AB_MEM_DEPTH)) # 5
C_ADDR_W      = int(math.log2(C_MEM_DEPTH)) # 5
AB_BASEADDR_W = AB_ADDR_W - 3
C_BASEADDR_W  = C_ADDR_W - 3

def to_machine_code(instruction):
    #print(instruction)
    machine_code = ''
    expected_output = ''
    instruction_data = instruction.split()
    op = instruction_data[0]
    #print(op)
    #print(instruction)
    match op:
        case "NOOP":
            opcode = '000000'
            machine_code = f'{'0'*(FLIT_WIDTH-6)}_{opcode}\n'
            expected_output = f'{'0'*(FLIT_WIDTH-6)}_{opcode}\n'
        case "WRITE8":
            opcode = '010000'
            Addr_dest = int(instruction_data[1])
            if(Addr_dest < 0 or Addr_dest > AB_MEM_DEPTH - 1):
                print("WARNING: Address out of bounds")
                return ''
            if(Addr_dest > AB_MEM_DEPTH - 1 - DIM*4):
                print("WARNING: Cannot overwrite identity matrix")
                return ''
            Addr_dest = f'{'0'*(6-AB_ADDR_W)}{to_signed_nbit_binary(Addr_dest, AB_ADDR_W)}'
            bracket_i = instruction.find('[')
            bracket_j = instruction.find(']')
            data = instruction[bracket_i+1:bracket_j].split(sep=', ')
            data = [f'_{to_signed_nbit_binary(int(n), AB_WIDTH)}' for n in data]
            data_string = ''
            for i in range(len(data)):
                if (i) % int(FLIT_WIDTH/AB_WIDTH) == 0:
                    data_string += '\n'
                data_string += data[i]
            machine_code = f'{Addr_dest}{f'_{'0'*6}'*3}_00_{opcode}{data_string}\n'
            expected_output = f'{Addr_dest}{f'_{'0'*6}'*3}_00_{opcode}\n'
        case "WRITE32":
            opcode = '010010'
            Addr_dest = int(instruction_data[1])
            if(Addr_dest < 0 or Addr_dest > C_MEM_DEPTH - 1):
                print("WARNING: Address out of bounds")
                return ''
            if(Addr_dest > C_MEM_DEPTH - 1 - DIM*2):
                print("WARNING: Cannot overwrite zero matrix")
                return ''
            Addr_dest = f'{'0'*(6-C_ADDR_W)}{to_signed_nbit_binary(Addr_dest, C_ADDR_W)}'
            bracket_i = instruction.find('[')
            bracket_j = instruction.find(']')
            data = instruction[bracket_i+1:bracket_j].split(sep=', ')
            data = [f'_{to_signed_nbit_binary(int(n), C_WIDTH)}' for n in data]
            data_string = ''
            for i in range(len(data)):
                if (i) % int(FLIT_WIDTH/C_WIDTH) == 0:
                    data_string += '\n'
                data_string += data[i]
            machine_code = f'{Addr_dest}{f'_{'0'*6}'*3}_00_{opcode}___{data_string}\n'
            expected_output = f'{Addr_dest}{f'_{'0'*6}'*3}_00_{opcode}\n'
        case "TRANSPOSE":
            opcode = '011001'
            BaseAddr_dest = int(instruction_data[1])
            BaseAddr_source = int(instruction_data[2])
            if(BaseAddr_dest < 0 or BaseAddr_dest > (AB_MEM_DEPTH/DIM - 1) or BaseAddr_source < 0 or BaseAddr_source > (AB_MEM_DEPTH/DIM - 1)):
                print("WARNING: Address out of bounds")
                return ''
            if(BaseAddr_source > (AB_MEM_DEPTH/DIM - 5)):
                BaseAddr_source = 7
            if(BaseAddr_dest > (AB_MEM_DEPTH/DIM - 5)):
                print("WARNING: Cannot overwrite identity matrix")
                return ''
            BaseAddr_dest = f'{'0'*(6-C_ADDR_W)}{to_signed_nbit_binary(BaseAddr_dest, C_BASEADDR_W)}000'
            BaseAddr_source = f'{'0'*(6-AB_ADDR_W)}{to_signed_nbit_binary(BaseAddr_source, AB_BASEADDR_W)}000'
            machine_code = f'{BaseAddr_dest}_{BaseAddr_source}{f'_{'0'*6}'*2}_00_{opcode}\n'
            expected_output = f'{BaseAddr_dest}_{BaseAddr_source}{f'_{'0'*6}'*2}_00_{opcode}\n'
        case "WRITE_CSR":
            opcode = '010100'
            data_string = instruction_data[1]
            data_string = f'\n_{data_string[:FLIT_WIDTH+3]}\n{data_string[FLIT_WIDTH+3:]}'
            machine_code = f'{'0'*(FLIT_WIDTH-6)}_{opcode}{data_string}\n'
            expected_output = f'{'0'*(FLIT_WIDTH-6)}_{opcode}\n'
        case "ERROR_CSR":
            opcode = '011100'
            machine_code = f'{'0'*(FLIT_WIDTH-6)}_{opcode}\n'
            expected_output = f'{'0'*(FLIT_WIDTH-6)}_{opcode}\n'
        case "READ_CSR":
            opcode = '001100'
            machine_code = f'{'0'*(FLIT_WIDTH-6)}_{opcode}\n'
            expected_output = f'{'0'*(FLIT_WIDTH-6)}_{opcode}___{'x'*8*AB_WIDTH}\n'
        case "READM8":
            opcode = '001001'
            BaseAddr_source = int(instruction_data[1])
            if(BaseAddr_source < 0 or BaseAddr_source > (AB_MEM_DEPTH/DIM - 1)):
                print("WARNING: Address out of bounds")
                return ''
            if(BaseAddr_source > 3):
                BaseAddr_source = 7
            BaseAddr_source = f'{'0'*(6-AB_ADDR_W)}{to_signed_nbit_binary(BaseAddr_source, AB_BASEADDR_W)}000'
            machine_code = f'{'0'*6}_{BaseAddr_source}{f'_{'0'*6}'*2}_00_{opcode}\n'
            expected_output = f'{'0'*6}_{BaseAddr_source}{f'_{'0'*6}'*2}_00_{opcode}___{'x'*64*AB_WIDTH}\n'
        case "READM32":
            opcode = '001011'
            BaseAddr_source = int(instruction_data[1])
            if(BaseAddr_source < 0 or BaseAddr_source > (C_MEM_DEPTH/DIM - 1)):
                print("WARNING: Address out of bounds")
                return ''
            if(BaseAddr_source > 1):
                BaseAddr_source = 7
            BaseAddr_source = f'{'0'*(6-C_ADDR_W)}{to_signed_nbit_binary(BaseAddr_source, C_BASEADDR_W)}000'
            machine_code = f'{'0'*6}_{BaseAddr_source}{f'_{'0'*6}'*2}_00_{opcode}\n'
            expected_output = f'{'0'*6}_{BaseAddr_source}{f'_{'0'*6}'*2}_00_{opcode}___{'x'*64*C_WIDTH}\n'
        case "READV8":
            opcode = '001000'
            Addr_source = int(instruction_data[1])
            if(Addr_source < 0 or Addr_source > AB_MEM_DEPTH - 1):
                print("WARNING: Address out of bounds")
                return ''
            if(Addr_source > 31):
                Addr_source = 63
            Addr_source = f'{'0'*(6-AB_ADDR_W)}{to_signed_nbit_binary(Addr_source, AB_ADDR_W)}'
            machine_code = f'{'0'*6}_{Addr_source}{f'_{'0'*6}'*2}_00_{opcode}\n'
            expected_output = f'{'0'*6}_{Addr_source}{f'_{'0'*6}'*2}_00_{opcode}___{'x'*8*AB_WIDTH}\n'
        case "READV32":
            opcode = '001010'
            Addr_source = int(instruction_data[1])
            if(Addr_source < 0 or Addr_source > C_MEM_DEPTH - 1):
                print("WARNING: Address out of bounds")
                return ''
            if(Addr_source > 15):
                Addr_source = 31
            Addr_source = f'{'0'*(6-C_ADDR_W)}{to_signed_nbit_binary(Addr_source, C_ADDR_W)}'
            machine_code = f'{'0'*6}_{Addr_source}{f'_{'0'*6}'*2}_00_{opcode}\n'
            expected_output = f'{'0'*6}_{Addr_source}{f'_{'0'*6}'*2}_00_{opcode}___{'x'*8*C_WIDTH}\n'
        case "LR":
            opcode = '111000'
            #opcode = '110000'
            BaseAddr_weight = int(instruction_data[1])
            if(BaseAddr_weight < 0 or BaseAddr_weight > (AB_MEM_DEPTH/DIM - 1)):
                print("WARNING: Address out of bounds")
                return ''
            if(BaseAddr_weight > 3):
                BaseAddr_weight = 7
            BaseAddr_weight = f'{'0'*(6-AB_ADDR_W)}{to_signed_nbit_binary(BaseAddr_weight, AB_BASEADDR_W)}000'
            machine_code = f'{'000000_'*3}{BaseAddr_weight}_00_{opcode}\n'
            expected_output = f'{'000000_'*3}{BaseAddr_weight}_00_{opcode}\n'
        case "LC":
            opcode = '110000'
            #opcode = '111000'
            BaseAddr_weight = int(instruction_data[1])
            if(BaseAddr_weight < 0 or BaseAddr_weight > (AB_MEM_DEPTH/DIM - 1)):
                print("WARNING: Address out of bounds")
                return ''
            if(BaseAddr_weight > 3):
                BaseAddr_weight = 7
            BaseAddr_weight = f'{'0'*(6-AB_ADDR_W)}{to_signed_nbit_binary(BaseAddr_weight, AB_BASEADDR_W)}000'
            machine_code = f'{'000000_'*3}{BaseAddr_weight}_00_{opcode}\n'
            expected_output = f'{'000000_'*3}{BaseAddr_weight}_00_{opcode}\n'
        case "CR":
            opcode = '100110'
            #opcode = '100100'
            BaseAddr_dest = int(instruction_data[1])
            BaseAddr_source = int(instruction_data[2])
            BaseAddr_acc = int(instruction_data[3])
            if(BaseAddr_dest < 0 or BaseAddr_dest > (C_MEM_DEPTH/DIM - 1) or BaseAddr_source < 0 or BaseAddr_source > (AB_MEM_DEPTH/DIM - 1) or BaseAddr_acc < 0 or BaseAddr_acc > (C_MEM_DEPTH/DIM - 1)):
                print("WARNING: Address out of bounds")
                return ''
            if(BaseAddr_dest > (C_MEM_DEPTH/DIM - 2)):
                print("WARNING: Cannot overwrite zero matrix")
                return ''
            BaseAddr_dest = f'0{to_signed_nbit_binary(BaseAddr_dest, C_BASEADDR_W)}000'
            BaseAddr_source = f'{'0'*(6-AB_ADDR_W)}{to_signed_nbit_binary(BaseAddr_source, AB_BASEADDR_W)}000'
            BaseAddr_acc = f'0{to_signed_nbit_binary(BaseAddr_acc, C_BASEADDR_W)}000'
            machine_code = f'{BaseAddr_dest}_{BaseAddr_source}_{BaseAddr_acc}_{'0'*6}_00_{opcode}\n'
            expected_output = f'{BaseAddr_dest}_{BaseAddr_source}_{BaseAddr_acc}_{'0'*6}_00_{opcode}\n'
        case "CC":
            opcode = '100100'
            #opcode = '100110'
            BaseAddr_dest = int(instruction_data[1])
            BaseAddr_source = int(instruction_data[2])
            BaseAddr_acc = int(instruction_data[3])
            if(BaseAddr_dest < 0 or BaseAddr_dest > (C_MEM_DEPTH/DIM - 1) or BaseAddr_source < 0 or BaseAddr_source > (AB_MEM_DEPTH/DIM - 1) or BaseAddr_acc < 0 or BaseAddr_acc > (C_MEM_DEPTH/DIM - 1)):
                print("WARNING: Address out of bounds")
                return ''
            if(BaseAddr_dest > (C_MEM_DEPTH/DIM - 2)):
                print("WARNING: Cannot overwrite zero matrix")
                return ''
            BaseAddr_dest = f'0{to_signed_nbit_binary(BaseAddr_dest, C_BASEADDR_W)}000'
            BaseAddr_source = f'{'0'*(6-AB_ADDR_W)}{to_signed_nbit_binary(BaseAddr_source, AB_BASEADDR_W)}000'
            BaseAddr_acc = f'0{to_signed_nbit_binary(BaseAddr_acc, C_BASEADDR_W)}000'
            machine_code = f'{BaseAddr_dest}_{BaseAddr_source}_{BaseAddr_acc}_{'0'*6}_00_{opcode}\n'
            expected_output = f'{BaseAddr_dest}_{BaseAddr_source}_{BaseAddr_acc}_{'0'*6}_00_{opcode}\n'
        case "LRCR" | "LCCR" | "LRCC" | "LCCC":
            opcode = f'11{int(op[1] == 'R')}1{int(op[3] == 'R')}0'
            #opcode = f'11{int(op[1] == 'C')}1{int(op[3] == 'C')}0'
            BaseAddr_dest = int(instruction_data[1])
            BaseAddr_source = int(instruction_data[2])
            BaseAddr_acc = int(instruction_data[3])
            BaseAddr_weight = int(instruction_data[4])
            if(BaseAddr_dest < 0 or BaseAddr_dest > (C_MEM_DEPTH/DIM - 1) or BaseAddr_source < 0 or BaseAddr_source > (AB_MEM_DEPTH/DIM - 1) or BaseAddr_acc < 0 or BaseAddr_acc > (C_MEM_DEPTH/DIM - 1) or BaseAddr_weight < 0 or BaseAddr_weight > (AB_MEM_DEPTH/DIM - 1)):
                print("WARNING: Address out of bounds")
                return ''
            if(BaseAddr_dest > (C_MEM_DEPTH/DIM - 2)):
                print("WARNING: Cannot overwrite zero matrix")
                return ''
            BaseAddr_dest = f'0{to_signed_nbit_binary(BaseAddr_dest, C_BASEADDR_W)}000'
            BaseAddr_source = f'{'0'*(6-AB_ADDR_W)}{to_signed_nbit_binary(BaseAddr_source, AB_BASEADDR_W)}000'
            BaseAddr_acc = f'0{to_signed_nbit_binary(BaseAddr_acc, C_BASEADDR_W)}000'
            BaseAddr_weight = f'{'0'*(6-AB_ADDR_W)}{to_signed_nbit_binary(BaseAddr_weight, AB_BASEADDR_W)}000'
            machine_code = f'{BaseAddr_dest}_{BaseAddr_source}_{BaseAddr_acc}_{BaseAddr_weight}_00_{opcode}\n'
            expected_output = f'{BaseAddr_dest}_{BaseAddr_source}_{BaseAddr_acc}_{BaseAddr_weight}_00_{opcode}\n'
        case _:
            machine_code = ''
    return machine_code

# print(to_machine_code("NOOP"))
# print(to_machine_code("WRITE8 1 [1, 2, 3, 4, 5, 6, 7, 8]"))
# print(to_machine_code("WRITE32 20 [1, 2, 3, 4, 5, 6, 7, 8]"))
# print(to_machine_code("TRANSPOSE 5 7"))
# print(to_machine_code("TRANSPOSE 1 2"))
# print(to_machine_code("WRITE_CSR 00000000_00000000_11111111_00000000_00000000_00000000_11111111_00000000"))
# print(to_machine_code("ERROR_CSR"))
# print(to_machine_code("READ_CSR"))
# print(to_machine_code("READM8 8")) # will throw a warning (address out of bounds)
# print(to_machine_code("READM32 0"))
# print(to_machine_code("READV8 4")) 
# print(to_machine_code("READV32 31"))
# print(to_machine_code("LR 3"))
# print(to_machine_code("LC 4"))
# print(to_machine_code("CR 1 2 3")) 
# print(to_machine_code("CC 1 0 0"))
# print(to_machine_code("LRCR 2 1 1 0"))
# print(to_machine_code("LCCR 3 1 0 1")) # will throw a warning (cannot overwrite zero matrix)
# print(to_machine_code("LRCC 0 1 2 3"))
# print(to_machine_code("LCCC 1 2 3 4"))

def to_flits(output, width=8):
    if isinstance(output, np.ndarray) and output.ndim == 2:
        # matrix
        data = [[f'_{to_signed_nbit_binary(int(n), width)}' for n in row] for row in output]
        #print(data)
        data_string = ''
        i = 0
        for row in data:
            for n in row:
                if (i) % int(FLIT_WIDTH/width) == 0:
                    data_string += '\n0010_'
                data_string += n
                i = i + 1
    elif isinstance(output, np.ndarray) and output.ndim == 1:
        # array
        data = [f'_{to_signed_nbit_binary(int(n), width)}' for n in output]
        data_string = ''
        for i in range(len(data)):
            if (i) % int(FLIT_WIDTH/width) == 0:
                data_string += '\n0010_'
            data_string += data[i]
    else:
        # string
        data_string = ''
        i = -1
        #print(output)
        for c in output:
            #print(c)
            if c != '_' and c != '\n':
                i = i + 1
                #print('index incremented')
            if (i) % int(FLIT_WIDTH) == 0:
                #print(i, 'entered')
                #print(int(FLIT_WIDTH))
                if(i == 0):
                    data_string += '0010_'
                else:
                    data_string += '\n0010_'
            data_string += c
            
        #data_string = f'\n_{output[:FLIT_WIDTH+3]}\n{output[FLIT_WIDTH+3:]}'
    return data_string




### Some helper methods to convert instructions with matrices into larger instructions'
def WRITEM(M, Addr, size):
    Addr = Addr * DIM
    instructions = ''
    for row in M:
        m_string = f'[{int(row[0])}'
        for n in row[1:]:
            m_string += f', {int(n)}'
        m_string += ']'
        if size == 8:
            instructions += f"WRITE8 {Addr} {m_string}\n"
        elif size == 32:
            instructions += f"WRITE32 {Addr} {m_string}\n"
        Addr = Addr + 1
    return instructions

ADDITIONAL_DELAY = 100
def instructions_to_traces(benchmark_file, send_trace_file):
    with open(benchmark_file, 'r') as instructions, open(send_trace_file, 'w') as send_trace:
        for line in instructions:
            #print(line)
            line = line.strip()
            if(line == ''):
                send_trace.write('')
            elif(line == 'NOOP'):
                send_trace.write(f'0000_{to_machine_code(line)}\n')
            elif(line[0] == '#'):
                send_trace.write(f'{line}\n')
            else:
                if line[:5] == 'WRITE':
                    line = to_machine_code(line)
                    enters = line.count('\n')
                    line = line.replace('\n', '\n0001', enters - 1)
                    send_trace.write(f'0001_{line}\n')
                else:
                    send_trace.write(f'0001_{to_machine_code(line)}\n')
        # for i in range(ADDITIONAL_DELAY):
        #     send_trace.write(f'0000_{to_machine_code('NOOP')}\n')
        # send_trace.write('# END SIMULATION\n')
        # send_trace.write(f'0100_{to_machine_code('NOOP')}\n')
    return

def receive_to_traces(benchmark_file, recv_trace_file, outputs):
    i = 0
    with open(benchmark_file, 'r') as instructions, open(recv_trace_file, 'w') as recv_trace:
        for line in instructions:
            #print(line, outputs[i])
            line = line.strip()
            if(line == ''):
                recv_trace.write('')
            elif(line == 'NOOP'):
                recv_trace.write(f'0000_{to_machine_code(line)}\n')
            elif(line != '' and line[0] == '#'):
                recv_trace.write(f'{line}\n')
            else:
                if line[:5] == 'WRITE':
                    if line[5] == '_':
                        recv_trace.write(f'0010_{to_machine_code(line)[:FLIT_WIDTH+1]}\n') # COMMENT OUT IF NO HEADERS
                        recv_trace.write('')
                    else:
                        recv_trace.write(f'0010_{to_machine_code(line)[:FLIT_WIDTH+5]}\n') # COMMENT OUT IF NO HEADERS
                        recv_trace.write('')
                else:
                    recv_trace.write(f'0010_{to_machine_code(line)}') # COMMENT OUT IF NO HEADERS 
                    if line[:4] == 'READ':
                        print(line)
                        #recv_trace.write(f'0010_{to_machine_code(line)}') # UNCOMMENT IF NO HEADERS
                        if line[5] == '8':
                            recv_trace.write(f'{to_flits(outputs[i], AB_WIDTH)}\n')
                        else:
                            recv_trace.write(f'{to_flits(outputs[i], C_WIDTH)}\n')
                        i = i + 1
        recv_trace.write('# END SIMULATION\n')
        recv_trace.write(f'0100_{to_machine_code('NOOP')}\n')
    return


def gen_matrix(N, min_val, max_val):
    return [[random.randint(min_val, max_val) for _ in range(N)] for _ in range(N)]

import random
import numpy as np
A1 = np.arange(1, 65).reshape(8,8)
# print(WRITEM(np.identity(8), 8))
B2 = np.full((8,8), 2)
C12 = A1 @ B2

# instructions_to_traces('scripts/tpu_benchmark1.txt', 'v/Top_level/benchmark1_send_trace.tr')
# expected_outputs = [np.identity(8), A1, C12]
# receive_to_traces('scripts/tpu_benchmark1.txt', 'v/Top_level/benchmark1_recv_trace.tr', expected_outputs)
# instructions_to_traces('scripts/tpu_benchmark1.txt', 'v/Top_level/benchmark1_header_send_trace.tr')
# expected_outputs = [np.identity(8), A1, C12]
# receive_to_traces('scripts/tpu_benchmark1.txt', 'v/Top_level/benchmark1_header_recv_trace.tr', expected_outputs)

# instructions_to_traces('scripts/tpu_benchmark2.txt', 'v/Top_level/benchmark2_send_trace.tr')
# csr_out = f'{'x'*64}'
# M8_out = f'{f'{'xxxxxxxx'*4}'*16}'
# M32_out = f'{f'{'x'*32}'*64}'
# V8_out = f'{f'{'xxxxxxxx'*4}'*2}'
# V32_out = f'{f'{'x'*32}'*8}'
# expected_outputs2 = [csr_out, M8_out, M32_out, V8_out, V32_out]
# receive_to_traces('scripts/tpu_benchmark2.txt', 'v/Top_level/benchmark2_recv_trace.tr', expected_outputs2)

# print(WRITEM(np.zeros((8,8)) - 2147470000, 0, 32))
# print(WRITEM(np.zeros((8,8)) - 128, 5, 8))

# instructions_to_traces('scripts/tpu_benchmark2.txt', 'v/Top_level/benchmark2_send_trace.tr')
# ZERO = np.zeros((8, 8))
# C0 = np.array([
#     [0, 1, 1, 2, 3, 5, 8, 13],
#     [21, 34, 55, 89, 144, 233, 377, 610],
#     [987, 1597, 2584, 4181, 6765, 10946, 17711, 28657],
#     [46368, 75025, 121393, 196418, 317811, 514229, 832040, 1346269],
#     [0, 1, 1, 2, 3, 5, 8, 13],
#     [21, 34, 55, 89, 144, 233, 377, 610],
#     [987, 1597, 2584, 4181, 6765, 10946, 17711, 28657],
#     [46368, 75025, 121393, 196418, 317811, 514229, 832040, 1346269]
# ])
# C_MAX = np.zeros((8, 8)) + 2147470000
# C_MIN = np.zeros((8, 8)) - 2147470000
# MAX = np.zeros((8,8)) + 2147483647
# MIN = np.zeros((8,8)) - 2147483648
# inc = np.arange(1, 65).reshape(8,8)
# C1 = inc @ inc + C0
# #print(C1)
# A_rand_1 = np.array(
#     [[99, -34, -108, -80, 32, 60, 122, 19], 
#      [-77, -86, 84, -72, -49, -70, 26, 61], 
#      [25, 54, 50, 66, -29, -10, 51, 32], 
#      [93, -103, 117, 1, 54, 83, 4, -54], 
#      [-10, 103, -33, 108, 16, 106, 8, -10], 
#      [-71, 56, -108, 7, -77, 12, -95, 40], 
#      [-23, 0, 69, -57, 45, -65, -13, -27], 
#      [52, -9, 93, -59, -79, -65, -100, -20]]
# )
# #print(WRITEM(A_rand_1, 0, 8))
# B_rand_1 = np.array(
#     [[-113, 63, -54, 96, -108, -89, 48, -74], 
#      [-43, 108, -35, -98, 60, 67, -121, -7], 
#      [81, -66, 99, -89, 26, 122, 29, -9], 
#      [44, -46, 18, 4, 34, -8, 91, -73], 
#      [-101, -46, 82, -125, -33, -30, 38, -125], 
#      [-68, -102, -25, 31, 64, 88, -98, 55], 
#      [-61, 110, 64, -103, -80, -6, -23, 92], 
#      [115, -11, -124, 30, 22, -51, -61, -18]]
# )
# #print(B_rand_1)
# #print(WRITEM(B_rand_1, 1, 8))
# C_rand_1 = np.array(
#     [[1906039880, -1294078670, -104540819, 1755856170, 76840551, -1326864146, -433331889, -1030540331], 
#      [842650909, -809944120, 304952898, -1696880831, -1877277853, -317969120, -1573138746, -1867370721], 
#      [2024817096, -1413621199, -1752308152, -678483176, -1453364263, -2080356960, -1261626396, 634775254], 
#      [-750098978, -578337390, -320766149, 1670702042, -950197373, 911634331, 1310237150, 1401627786], 
#      [-340445697, -317602231, 799943224, 1473678361, 1759221691, 561662828, -1026105495, -1197732966], 
#      [367919796, -802892472, 768869943, -67730807, 2023715610, -39463630, -1221142543, -1321087078], 
#      [-1731595474, 1557516857, 639185468, -2086145159, 1046312187, -1942818419, 1092142395, -1196698882], 
#      [1175340704, 447380844, -1869623173, -1815681976, -1518565232, 1939742372, 1689701687, -1133824734]]
# )
# #print(C_rand_1)
# #print(WRITEM(C_rand_1, 0, 32))
# ABC_rand_1 = A_rand_1 @ B_rand_1 + C_rand_1
# A_rand_2 = np.array(
#     [[-13, -109, -36, -35, -23, 75, 118, -12], 
#      [111, 114, -48, 34, 24, 44, -9, 87], 
#      [-41, -105, -95, -60, -83, 29, -9, 12], 
#      [-55, 92, -45, 26, -92, 86, -74, 73], 
#      [13, 100, 29, 39, -53, 92, 107, 35], 
#      [-51, -10, -93, -75, 79, -68, -49, 27], 
#      [53, 85, 54, 41, -85, -51, 80, 53], 
#      [-103, 61, -10, -12, -89, -68, -122, -86]]
# )
# #print(A_rand_2)
# #print(WRITEM(A_rand_2, 2, 8))
# B_rand_2 = np.array(
#     [[-119, -9, 112, 34, -76, -55, 84, -42], 
#      [108, 88, 96, -45, -61, -25, -67, -14], 
#      [-117, -23, 72, -25, -77, -79, -78, -101], 
#      [-101, -123, 71, 92, 66, -37, -11, -26], 
#      [-114, 81, 51, -41, 26, 84, 68, -69], 
#      [-36, 53, 66, 47, 77, -116, -70, 46], 
#      [0, 117, 25, -93, 37, -64, -105, 51], 
#      [2, -5, -101, -81, -29, -36, -42, 78]]
# )
# #print(B_rand_2)
# #print(WRITEM(B_rand_2, 3, 8))
# C_rand_2 = np.array(
#     [[-414899475, 1478206584, -1731780381, -2058374968, 464419244, 1469562934, -1262059370, -473203815], 
#      [1934818167, -1537189292, -77940516, 438831378, -509337547, 602048661, 1878974428, 1021063447], 
#      [403940573, 657880447, 1967862938, -817959662, 237033179, 1471595085, -528063547, -1582874228], 
#      [447369337, 675089261, -1772397650, -632659346, 42555039, 447663445, -740362313, -52617206], 
#      [-1728740891, 1996818067, -756113179, 1222121303, 1723591261, 2129486945, 2010372684, -1784708225], 
#      [856078593, -753837312, 151457864, 241629886, 422296314, 766874071, 1003503289, 1748661191], 
#      [-1080502296, 499643176, -837490291, -1194781508, -705424037, 1912986061, 831469188, 1025594630], 
#      [2009882787, -1586440742, 1463188182, -540356462, 138967463, 1305838590, -738217779, -598513115]]
# )
# #print(C_rand_2)
# #print(WRITEM(C_rand_2, 0, 32))
# ABC_rand_2 = A_rand_2 @ B_rand_2 + C_rand_2

# expected_outputs2 = [ZERO, ZERO, ZERO, C0, MAX, MIN, C1, ABC_rand_1, ABC_rand_2]
# receive_to_traces('scripts/tpu_benchmark2.txt', 'v/Top_level/benchmark2_recv_trace.tr', expected_outputs2)

instructions_to_traces('scripts/tpu_benchmark3.txt', 'v/Top_level/benchmark3_send_trace.tr')
inc = np.arange(1, 65).reshape(8,8)
C0 = np.array([
    [0, 1, 1, 2, 3, 5, 8, 13],
    [21, 34, 55, 89, 144, 233, 377, 610],
    [987, 1597, 2584, 4181, 6765, 10946, 17711, 28657],
    [46368, 75025, 121393, 196418, 317811, 514229, 832040, 1346269],
    [0, 1, 1, 2, 3, 5, 8, 13],
    [21, 34, 55, 89, 144, 233, 377, 610],
    [987, 1597, 2584, 4181, 6765, 10946, 17711, 28657],
    [46368, 75025, 121393, 196418, 317811, 514229, 832040, 1346269]
])
inc_T = inc.T
V8 = np.arange(1,9)
V0 = np.zeros(8)
C = inc @ inc
CSR = '11111111_11111111_11111111_11111111_11111111_11111111_11111111_10000001'
expected_outputs3 = [inc_T, C0, V8, V0, inc, inc, inc, inc, C, C, CSR]
receive_to_traces('scripts/tpu_benchmark3.txt', 'v/Top_level/benchmark3_recv_trace.tr', expected_outputs3)


# A1 = np.arange(1, 65).reshape(8,8)
# print(WRITEM(np.identity(8), 8))
# B2 = np.full((8,8), 2)
# C12 = A1 @ B2
# print(WRITEM(A1, 0, 8))
# print(WRITEM(B2, 1, 8))
# print(to_flits(C12, 32))
# print(to_flits(C12[0], 8))
# print(to_flits('00000000_00000000_11111111_00000000_00000000_00000000_11111111_00000000'))

# with open('scripts/tpu_benchmark1.txt', 'w') as instruction_file:
#     instruction_file.write(WRITEM(A1, 0))
#     instruction_file.write(WRITEM(B2, 1))
#     instruction_file.write(to_machine_code("LR 62"))
#     instruction_file.write(to_machine_code("CR 2 62 63"))
#     instruction_file.write(to_machine_code("READM16 2"))
#     instruction_file.write(to_machine_code("LCCR 3 0 63 1"))
#     instruction_file.write(to_machine_code("READM16 3"))
#     instruction_file.write(to_machine_code("CR 4 0 63"))
#     instruction_file.write(to_machine_code("READM16 4"))
