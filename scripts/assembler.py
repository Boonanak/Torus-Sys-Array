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
AB_MEM_DEPTH  = 32
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
            for n in data:
                data_string += n
            machine_code = f'{Addr_dest}{f'_{'0'*6}'*3}_00_{opcode}___{data_string}\n'
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
            for n in data:
                data_string += n
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
            machine_code = f'{'0'*(FLIT_WIDTH-6)}_{opcode}___{data_string}\n'
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
            BaseAddr_source = f'0{to_signed_nbit_binary(BaseAddr_source, AB_BASEADDR_W)}000'
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
            BaseAddr_source = f'0{to_signed_nbit_binary(BaseAddr_source, AB_BASEADDR_W)}000'
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
            BaseAddr_source = f'0{to_signed_nbit_binary(BaseAddr_source, AB_BASEADDR_W)}000'
            BaseAddr_acc = f'0{to_signed_nbit_binary(BaseAddr_acc, C_BASEADDR_W)}000'
            BaseAddr_weight = f'0{to_signed_nbit_binary(BaseAddr_weight, AB_BASEADDR_W)}000'
            machine_code = f'{BaseAddr_dest}_{BaseAddr_source}_{BaseAddr_acc}_{BaseAddr_weight}_00_{opcode}\n'
            expected_output = f'{BaseAddr_dest}_{BaseAddr_source}_{BaseAddr_acc}_{BaseAddr_weight}_00_{opcode}\n'
        case _:
            machine_code = ''
    return machine_code

print(to_machine_code("NOOP"))
print(to_machine_code("WRITE8 1 [1, 2, 3, 4, 5, 6, 7, 8]"))
print(to_machine_code("WRITE32 31 [1, 2, 3, 4, 5, 6, 7, 8]")) # will throw a warning (cannot overwrite zero matrix)
print(to_machine_code("TRANSPOSE 5 7")) # will throw a warning (address out of bounds)
print(to_machine_code("TRANSPOSE 1 2"))
print(to_machine_code("WRITE_CSR 00000000_00000000_11111111_00000000_00000000_00000000_11111111_00000000"))
print(to_machine_code("ERROR_CSR"))
print(to_machine_code("READ_CSR"))
print(to_machine_code("READM8 4")) # will throw a warning (address out of bounds)
print(to_machine_code("READM32 0"))
print(to_machine_code("READV8 4")) 
print(to_machine_code("READV32 31"))
print(to_machine_code("LR 3"))
print(to_machine_code("LC 4")) # will throw a warning (address out of bounds)
print(to_machine_code("CR 1 2 3")) 
print(to_machine_code("CC 1 0 0"))
print(to_machine_code("LRCR 2 1 1 0"))
print(to_machine_code("LCCR 3 1 0 1")) # will throw a warning (cannot overwrite zero matrix)
print(to_machine_code("LRCC 0 1 2 3"))
print(to_machine_code("LCCC 1 2 3 4")) # will throw a warning (address out of bounds)




### Some helper methods to convert instructions with matrices into larger instructions'
def WRITEM(M, Addr):
    Addr = Addr * 8
    instructions = ''
    for row in M:
        m_string = f'[{int(row[0])}'
        for n in row[1:]:
            m_string += f', {int(n)}'
        m_string += ']'
        instructions += to_machine_code(f"WRITE {Addr} {m_string}")
        Addr = Addr + 1
    return instructions

import random
import numpy as np
A1 = np.arange(1, 65).reshape(8,8)
# print(WRITEM(np.identity(8), 8))
B2 = np.full((8,8), 2)
C12 = A1 @ B2
# print(WRITEM(A1, 0))
# print(WRITEM(B2, 1))

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
