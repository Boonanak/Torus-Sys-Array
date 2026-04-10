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

def to_machine_code(instruction):
    space_i = instruction.find(' ')
    op = instruction[:space_i] if space_i > 0 else instruction
    instruction_data =''
    if(space_i > 0):
        instruction_data = instruction[space_i+1:]
    match op:
        case "WRITE":
            opcode = '00001'
            space_i = instruction_data.find(' ')
            Addr = f'{to_signed_nbit_binary(int(instruction_data[:space_i]), 10)}'
            data = instruction_data[space_i+2:len(instruction_data)-1].split(sep=', ')
            data = [f'_{to_signed_nbit_binary(int(n), 8)}' for n in data]
            data_string = ''
            for n in data:
                data_string += n
            parity = False
            for bit in data_string:
                if bit == '1':
                    parity = not parity
            return f'{opcode}_{Addr}_{int(parity)}{data_string}\n'
        case "READM":
            opcode = '00010'
            instruction_data = instruction_data.split()
            type = instruction_data[0] == 'R'
            BaseAddr = instruction_data[1]
            BaseAddr = f'{to_signed_nbit_binary(int(BaseAddr), 6)}'
            length = instruction_data[2]
            length = f'{to_signed_nbit_binary(int(length), 4)}'
            return f'{opcode}_{int(type)}_{BaseAddr}_{length}\n'
        case "READV":
            opcode = '00011'
            Addr = to_signed_nbit_binary(int(instruction_data), 10)
            return f'{opcode}_{Addr}_0\n'
        case "LOADB":
            opcode = '00100'
            instruction_data = instruction_data.split()
            type = instruction_data[0] == 'R'
            BaseAddr = instruction_data[1]
            BaseAddr = f'{to_signed_nbit_binary(int(BaseAddr), 6)}'
            return f'{opcode}_{int(type)}_{BaseAddr}_0000\n'
        case "COMPUTE":
            opcode = '00101'
            instruction_data = instruction_data.split()
            type = instruction_data[0] == 'R'
            BaseAddr = instruction_data[1]
            BaseAddr = f'{to_signed_nbit_binary(int(BaseAddr), 6)}'
            DestAddr = instruction_data[2]
            DestAddr = f'{to_signed_nbit_binary(int(DestAddr), 6)}'
            AccAddr = instruction_data[3]
            AccAddr = f'{to_signed_nbit_binary(int(AccAddr), 6)}'
            UseAcc = instruction_data[4]
            return f'{opcode}_{int(type)}_{BaseAddr}_{DestAddr}_{AccAddr}_{UseAcc}_0000000\n'
        case "WRITET":
            opcode = '00111'
            instruction_data = instruction_data.split()
            BaseAddr = instruction_data[0]
            BaseAddr = f'{to_signed_nbit_binary(int(BaseAddr), 6)}'
            DestAddr = instruction_data[1]
            DestAddr = f'{to_signed_nbit_binary(int(DestAddr), 6)}'
            return f'{opcode}_{BaseAddr}_{DestAddr}_000000000000000\n'
        case "ERROR":
            opcode = '11111'
            return f'{opcode}_00000000000\n'
        case "NOOP":
            opcode = '00000'
            return f'{opcode}_00000000000\n'


print(to_machine_code("WRITE 1 [2, 4, 6, 8]"))
print(to_machine_code("READM R 15 8"))
print(to_machine_code("READV 54"))
print(to_machine_code("LOADB C 21"))
print(to_machine_code("COMPUTE R 2 4 3 1"))
print(to_machine_code("WRITET 5 6"))
print(to_machine_code("ERROR"))
print(to_machine_code("NOOP"))

### Some helper methods to convert instructions with matrices into larger instructions'
def WRITEM(M, Addr):
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
print(WRITEM(np.identity(8), 8))

with open('scripts/tpu_benchmark1.txt', 'w') as instruction_file:
    instruction_file.write(WRITEM(np.identity(8), 0))
    instruction_file.write(WRITEM(np.identity(8), 8))
    instruction_file.write(WRITEM(np.zeros((8,8)), 16))
    instruction_file.write(to_machine_code("LOADB R 8"))
    instruction_file.write(to_machine_code("COMPUTE R 0 24 16 0"))
    instruction_file.write(to_machine_code("READM R 24 8"))