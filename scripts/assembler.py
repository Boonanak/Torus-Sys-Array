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
# 010000 = 16: WRITE <Addr> [<data1>, <data2>, ...]
# 011001 = 25: TRANSPOSE <BaseAddr_source> <BaseAddr_dest>
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
    machine_code = ''
    expected_output = ''
    instruction_data = instruction.split()
    op = instruction_data[0]
    #print(op)
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
            if(Addr_dest > AB_MEM_DEPTH - 1 - DIM):
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
            if(Addr_dest > C_MEM_DEPTH - 1 - DIM):
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
            if(BaseAddr_dest > (AB_MEM_DEPTH/DIM - 2)):
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
            BaseAddr_source = f'{'0'*(6-AB_ADDR_W)}{to_signed_nbit_binary(BaseAddr_source, AB_BASEADDR_W)}000'
            machine_code = f'{'0'*6}_{BaseAddr_source}{f'_{'0'*6}'*2}_00_{opcode}\n'
            expected_output = f'{'0'*6}_{BaseAddr_source}{f'_{'0'*6}'*2}_00_{opcode}___{'x'*64*AB_WIDTH}\n'
        case "READM32":
            opcode = '001011'
            BaseAddr_source = int(instruction_data[1])
            if(BaseAddr_source < 0 or BaseAddr_source > (C_MEM_DEPTH/DIM - 1)):
                print("WARNING: Address out of bounds")
                return ''
            BaseAddr_source = f'{'0'*(6-C_ADDR_W)}{to_signed_nbit_binary(BaseAddr_source, C_BASEADDR_W)}000'
            machine_code = f'{'0'*6}_{BaseAddr_source}{f'_{'0'*6}'*2}_00_{opcode}\n'
            expected_output = f'{'0'*6}_{BaseAddr_source}{f'_{'0'*6}'*2}_00_{opcode}___{'x'*64*C_WIDTH}\n'
        case "READV8":
            opcode = '001000'
            Addr_source = int(instruction_data[1])
            if(Addr_source < 0 or Addr_source > AB_MEM_DEPTH - 1):
                print("WARNING: Address out of bounds")
                return ''
            Addr_source = f'{'0'*(6-AB_ADDR_W)}{to_signed_nbit_binary(Addr_source, AB_ADDR_W)}'
            machine_code = f'{'0'*6}_{Addr_source}{f'_{'0'*6}'*2}_00_{opcode}\n'
            expected_output = f'{'0'*6}_{Addr_source}{f'_{'0'*6}'*2}_00_{opcode}___{'x'*8*AB_WIDTH}\n'
        case "READV32":
            opcode = '001010'
            Addr_source = int(instruction_data[1])
            if(Addr_source < 0 or Addr_source > C_MEM_DEPTH - 1):
                print("WARNING: Address out of bounds")
                return ''
            Addr_source = f'{'0'*(6-C_ADDR_W)}{to_signed_nbit_binary(Addr_source, C_ADDR_W)}'
            machine_code = f'{'0'*6}_{Addr_source}{f'_{'0'*6}'*2}_00_{opcode}\n'
            expected_output = f'{'0'*6}_{Addr_source}{f'_{'0'*6}'*2}_00_{opcode}___{'x'*8*C_WIDTH}\n'
        case "LR":
            opcode = '111000'
            BaseAddr_weight = int(instruction_data[1])
            if(BaseAddr_weight < 0 or BaseAddr_weight > (AB_MEM_DEPTH/DIM - 1)):
                print("WARNING: Address out of bounds")
                return ''
            BaseAddr_weight = f'{'0'*(6-AB_ADDR_W)}{to_signed_nbit_binary(BaseAddr_weight, AB_BASEADDR_W)}000'
            machine_code = f'{'000000_'*3}{BaseAddr_weight}_00_{opcode}\n'
            expected_output = f'{'000000_'*3}{BaseAddr_weight}_00_{opcode}\n'
        case "LC":
            opcode = '110000'
            BaseAddr_weight = int(instruction_data[1])
            if(BaseAddr_weight < 0 or BaseAddr_weight > (AB_MEM_DEPTH/DIM - 1)):
                print("WARNING: Address out of bounds")
                return ''
            BaseAddr_weight = f'{'0'*(6-AB_ADDR_W)}{to_signed_nbit_binary(BaseAddr_weight, AB_BASEADDR_W)}000'
            machine_code = f'{'000000_'*3}{BaseAddr_weight}_00_{opcode}\n'
            expected_output = f'{'000000_'*3}{BaseAddr_weight}_00_{opcode}\n'
        case "CR":
            opcode = '100110'
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
        data_string = f'\n_{output[:FLIT_WIDTH+3]}\n{output[FLIT_WIDTH+3:]}'
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
            if(line == 'NOOP'):
                send_trace.write(f'0000_{to_machine_code(line)}\n')
            elif(line[0] == '#'):
                send_trace.write(f'{line}\n')
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
            #print(line)
            line = line.strip()
            if(line == 'NOOP'):
                recv_trace.write(f'0000_{to_machine_code(line)}\n')
            elif(line[0] == '#'):
                recv_trace.write(f'{line}\n')
            else:
                if line[:5] == 'WRITE':
                    if line[5] == '_':
                        recv_trace.write(f'0010_{to_machine_code(line)[:FLIT_WIDTH+1]}\n')
                    else:
                        recv_trace.write(f'0010_{to_machine_code(line)[:FLIT_WIDTH+5]}\n')
                else:
                    print('receive side non-write instruction')
                    print(f'0010_{to_machine_code(line)}\n')
                    recv_trace.write(f'0010_{to_machine_code(line)}')
                    if line[:4] == 'READ':
                        if line[5] == '8':
                            recv_trace.write(f'{to_flits(outputs[i], AB_WIDTH)}\n')
                        else:
                            recv_trace.write(f'{to_flits(outputs[i], C_WIDTH)}\n')
        recv_trace.write('# END SIMULATION\n')
        recv_trace.write(f'0100_{to_machine_code('NOOP')}\n')
    return


import random
import numpy as np
A1 = np.arange(1, 65).reshape(8,8)
# print(WRITEM(np.identity(8), 8))
B2 = np.full((8,8), 2)
C12 = A1 @ B2

#instructions_to_traces('scripts/tpu_benchmark1.txt', 'v/Top_level/benchmark1_send_trace.tr')
expected_outputs = [np.identity(8), A1, C12]
receive_to_traces('scripts/tpu_benchmark1.txt', 'v/Top_level/benchmark1_recv_trace.tr', expected_outputs)

import random
import numpy as np
A1 = np.arange(1, 65).reshape(8,8)
# print(WRITEM(np.identity(8), 8))
B2 = np.full((8,8), 2)
C12 = A1 @ B2
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
