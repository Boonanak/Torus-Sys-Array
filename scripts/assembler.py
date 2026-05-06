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
DIM        = 8
AB_WIDTH   = 8
C_WIDTH    = 32
FLIT_WIDTH = 32
MEM_DEPTH  = 32
ADDR_W     = int(math.log2(MEM_DEPTH))
BASEADDR_W = ADDR_W - 3

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
            Addr_dest = instruction_data[1]
            if(Addr_dest[0] == 'C'):
                print("WARNING: Cannot write int8 vector to C bank")
                return ''
            Addr_dest = int(Addr_dest[1:])
            if(Addr_dest < 0 or Addr_dest > 31):
                print("WARNING: Address out of bounds")
                return ''
            Addr_dest = f'{to_signed_nbit_binary(Addr_dest, ADDR_W)}'
            bracket_i = instruction.find('[')
            bracket_j = instruction.find(']')
            data = instruction[bracket_i+1:bracket_j].split(sep=', ')
            data = [f'_{to_signed_nbit_binary(int(n), AB_WIDTH)}' for n in data]
            data_string = ''
            for n in data:
                data_string += n
            machine_code = f'{Addr_dest}{f'_{'0'*5}'*3}_{'0'*6}_{opcode}___{data_string}\n'
            expected_output = f'{Addr_dest}{f'_{'0'*5}'*3}_{'0'*6}_{opcode}\n'
        case "WRITE32":
            opcode = '010010'
            Addr_dest = instruction_data[1]
            if(Addr_dest[0] == 'A' or Addr_dest[0] == 'B'):
                print("WARNING: Cannot write int32 vector to AB bank")
                return ''
            Addr_dest = int(Addr_dest[1:])
            if(Addr_dest < 0 or Addr_dest > 31):
                print("WARNING: Address out of bounds")
                return ''
            Addr_dest = f'{to_signed_nbit_binary(Addr_dest, ADDR_W)}'
            bracket_i = instruction.find('[')
            bracket_j = instruction.find(']')
            data = instruction[bracket_i+1:bracket_j].split(sep=', ')
            data = [f'_{to_signed_nbit_binary(int(n), C_WIDTH)}' for n in data]
            data_string = ''
            for n in data:
                data_string += n
            machine_code = f'{Addr_dest}{f'_{'0'*5}'*3}_{'0'*6}_{opcode}___{data_string}\n'
            expected_output = f'{Addr_dest}{f'_{'0'*5}'*3}_{'0'*6}_{opcode}\n'
        case "TRANSPOSE":
            opcode = '011001'
            BaseAddr_dest = instruction_data[1]
            BaseAddr_source = instruction_data[2]
            if(BaseAddr_dest[0] == 'C' or BaseAddr_source[0] == 'C'):
                print("WARNING: Cannot transpose int32 vector")
                return ''
            BaseAddr_dest = int(BaseAddr_dest[1:])
            BaseAddr_source = int(BaseAddr_source[1:])
            if(BaseAddr_dest < 0 or BaseAddr_dest > 3 or BaseAddr_source < 0 or BaseAddr_source > 3):
                print("WARNING: Address out of bounds")
                return ''
            BaseAddr_dest = f'{to_signed_nbit_binary(BaseAddr_dest, BASEADDR_W)}000'
            BaseAddr_source = f'{to_signed_nbit_binary(BaseAddr_source, BASEADDR_W)}000'
            machine_code = f'{BaseAddr_dest}_{BaseAddr_source}{f'_{'0'*5}'*2}_{'0'*6}_{opcode}\n'
            expected_output = f'{BaseAddr_dest}_{BaseAddr_source}{f'_{'0'*5}'*2}_{'0'*6}_{opcode}\n'
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
            BaseAddr_source = instruction_data[1]
            if(BaseAddr_source[0] == 'C'):
                print("WARNING: Cannot read int8 vector from C bank")
                return ''
            BaseAddr_source = int(BaseAddr_source[1:])
            if(BaseAddr_source < 0 or BaseAddr_source > 3):
                print("WARNING: Address out of bounds")
                return ''
            BaseAddr_source = f'{to_signed_nbit_binary(BaseAddr_source, BASEADDR_W)}000'
            machine_code = f'{'0'*5}_{BaseAddr_source}{f'_{'0'*5}'*2}_{'0'*6}_{opcode}\n'
            expected_output = f'{'0'*5}_{BaseAddr_source}{f'_{'0'*5}'*2}_{'0'*6}_{opcode}___{'x'*64*AB_WIDTH}\n'
        case "READM32":
            opcode = '001011'
            BaseAddr_source = instruction_data[1]
            if(BaseAddr_source[0] == 'A' or BaseAddr_source[0] == 'B'):
                print("WARNING: Cannot read int32 vector from AB bank")
                return ''
            BaseAddr_source = int(BaseAddr_source[1:])
            if(BaseAddr_source < 0 or BaseAddr_source > 3):
                print("WARNING: Address out of bounds")
                return ''
            BaseAddr_source = f'{to_signed_nbit_binary(BaseAddr_source, BASEADDR_W)}000'
            machine_code = f'{'0'*5}_{BaseAddr_source}{f'_{'0'*5}'*2}_{'0'*6}_{opcode}\n'
            expected_output = f'{'0'*5}_{BaseAddr_source}{f'_{'0'*5}'*2}_{'0'*6}_{opcode}___{'x'*64*C_WIDTH}\n'
        case "READV8":
            opcode = '001000'
            Addr_source = instruction_data[1]
            if(Addr_source[0] == 'C'):
                print("WARNING: Cannot read int8 vector from C bank")
                return ''
            Addr_source = int(Addr_source[1:])
            if(Addr_source < 0 or Addr_source > 31):
                print("WARNING: Address out of bounds")
                return ''
            Addr_source = f'{to_signed_nbit_binary(Addr_source, ADDR_W)}'
            machine_code = f'{'0'*5}_{Addr_source}{f'_{'0'*5}'*2}_{'0'*6}_{opcode}\n'
            expected_output = f'{'0'*5}_{Addr_source}{f'_{'0'*5}'*2}_{'0'*6}_{opcode}___{'x'*8*AB_WIDTH}\n'
        case "READV32":
            opcode = '001010'
            Addr_source = instruction_data[1]
            if(Addr_source[0] == 'A' or Addr_source[0] == 'B'):
                print("WARNING: Cannot read int32 vector from AB bank")
                return ''
            Addr_source = int(Addr_source[1:])
            if(Addr_source < 0 or Addr_source > 31):
                print("WARNING: Address out of bounds")
                return ''
            Addr_source = f'{to_signed_nbit_binary(Addr_source, ADDR_W)}'
            machine_code = f'{'0'*5}_{Addr_source}{f'_{'0'*5}'*2}_{'0'*6}_{opcode}\n'
            expected_output = f'{'0'*5}_{Addr_source}{f'_{'0'*5}'*2}_{'0'*6}_{opcode}___{'x'*8*C_WIDTH}\n'
        case "LR":
            opcode = '111000'
            BaseAddr_weight = instruction_data[1]
            if(BaseAddr_weight[0] == 'C'):
                print("WARNING: Cannot read weights vector from C bank")
                return ''
            BaseAddr_weight = int(BaseAddr_weight[1:])
            if(BaseAddr_weight < 0 or BaseAddr_weight > 3):
                print("WARNING: Address out of bounds")
                return ''
            BaseAddr_weight = f'{to_signed_nbit_binary(BaseAddr_weight, BASEADDR_W)}000'
            machine_code = f'{'00000_'*3}{BaseAddr_weight}_000000_{opcode}\n'
            expected_output = f'{'00000_'*3}{BaseAddr_weight}_000000_{opcode}\n'
        case "LC":
            opcode = '110000'
            BaseAddr_weight = instruction_data[1]
            if(BaseAddr_weight[0] == 'C'):
                print("WARNING: Cannot read weights vector from C bank")
                return ''
            BaseAddr_weight = int(BaseAddr_weight[1:])
            if(BaseAddr_weight < 0 or BaseAddr_weight > 3):
                print("WARNING: Address out of bounds")
                return ''
            BaseAddr_weight = f'{to_signed_nbit_binary(BaseAddr_weight, BASEADDR_W)}000'
            machine_code = f'{'00000_'*3}{BaseAddr_weight}_000000_{opcode}\n'
            expected_output = f'{'00000_'*3}{BaseAddr_weight}_000000_{opcode}\n'
        case "CR":
            opcode = '100110'
            BaseAddr_dest = instruction_data[1]
            BaseAddr_source = instruction_data[2]
            BaseAddr_acc = instruction_data[3]
            if(BaseAddr_dest[0] == 'A' or BaseAddr_dest[0] == 'B'):
                print("WARNING: destination address cannot be in AB bank")
                return ''
            if(BaseAddr_acc[0] == 'A' or BaseAddr_acc[0] == 'B'):
                print("WARNING: accumulation address cannot be in AB bank")
                return ''
            if(BaseAddr_source[0] == 'C'):
                print("WARNING: source address cannot be in C bank")
                return ''
            BaseAddr_dest = int(BaseAddr_dest[1:])
            BaseAddr_source = int(BaseAddr_source[1:])
            BaseAddr_acc = int(BaseAddr_acc[1:])
            if(BaseAddr_dest < 0 or BaseAddr_dest > 3 or BaseAddr_source < 0 or BaseAddr_source > 3 or BaseAddr_acc < 0 or BaseAddr_acc > 3):
                print("WARNING: Address out of bounds")
                return ''
            BaseAddr_dest = f'{to_signed_nbit_binary(BaseAddr_dest, BASEADDR_W)}000'
            BaseAddr_source = f'{to_signed_nbit_binary(BaseAddr_source, BASEADDR_W)}000'
            BaseAddr_acc = f'{to_signed_nbit_binary(BaseAddr_acc, BASEADDR_W)}000'
            machine_code = f'{BaseAddr_dest}_{BaseAddr_source}_{BaseAddr_acc}_{'0'*5}_000000_{opcode}\n'
            expected_output = f'{BaseAddr_dest}_{BaseAddr_source}_{BaseAddr_acc}_{'0'*5}_000000_{opcode}\n'
        case "CC":
            opcode = '100100'
            BaseAddr_dest = instruction_data[1]
            BaseAddr_source = instruction_data[2]
            BaseAddr_acc = instruction_data[3]
            if(BaseAddr_dest[0] == 'A' or BaseAddr_dest[0] == 'B'):
                print("WARNING: destination address cannot be in AB bank")
                return ''
            if(BaseAddr_acc[0] == 'A' or BaseAddr_acc[0] == 'B'):
                print("WARNING: accumulation address cannot be in AB bank")
                return ''
            if(BaseAddr_source[0] == 'C'):
                print("WARNING: source address cannot be in C bank")
                return ''
            BaseAddr_dest = int(BaseAddr_dest[1:])
            BaseAddr_source = int(BaseAddr_source[1:])
            BaseAddr_acc = int(BaseAddr_acc[1:])
            if(BaseAddr_dest < 0 or BaseAddr_dest > 3 or BaseAddr_source < 0 or BaseAddr_source > 3 or BaseAddr_acc < 0 or BaseAddr_acc > 3):
                print("WARNING: Address out of bounds")
                return ''
            BaseAddr_dest = f'{to_signed_nbit_binary(BaseAddr_dest, BASEADDR_W)}000'
            BaseAddr_source = f'{to_signed_nbit_binary(BaseAddr_source, BASEADDR_W)}000'
            BaseAddr_acc = f'{to_signed_nbit_binary(BaseAddr_acc, BASEADDR_W)}000'
            machine_code = f'{BaseAddr_dest}_{BaseAddr_source}_{BaseAddr_acc}_{'0'*5}_000000_{opcode}\n'
            expected_output = f'{BaseAddr_dest}_{BaseAddr_source}_{BaseAddr_acc}_{'0'*5}_000000_{opcode}\n'
        case "LRCR":
            opcode = '111110'
            BaseAddr_dest = instruction_data[1]
            BaseAddr_source = instruction_data[2]
            BaseAddr_acc = instruction_data[3]
            BaseAddr_weight = instruction_data[4]
            if(BaseAddr_dest[0] == 'A' or BaseAddr_dest[0] == 'B'):
                print("WARNING: destination address cannot be in AB bank")
                return ''
            if(BaseAddr_acc[0] == 'A' or BaseAddr_acc[0] == 'B'):
                print("WARNING: accumulation address cannot be in AB bank")
                return ''
            if(BaseAddr_source[0] == 'C'):
                print("WARNING: source address cannot be in C bank")
                return ''
            if(BaseAddr_weight[0] == 'C'):
                print("WARNING: weight address cannot be in C bank")
                return ''
            BaseAddr_dest = int(BaseAddr_dest[1:])
            BaseAddr_source = int(BaseAddr_source[1:])
            BaseAddr_acc = int(BaseAddr_acc[1:])
            BaseAddr_weight = int(BaseAddr_weight[1:])
            if(BaseAddr_dest < 0 or BaseAddr_dest > 3 or BaseAddr_source < 0 or BaseAddr_source > 3 or BaseAddr_acc < 0 or BaseAddr_acc > 3 or BaseAddr_weight < 0 or BaseAddr_weight > 3):
                print("WARNING: Address out of bounds")
                return ''
            BaseAddr_dest = f'{to_signed_nbit_binary(BaseAddr_dest, BASEADDR_W)}000'
            BaseAddr_source = f'{to_signed_nbit_binary(BaseAddr_source, BASEADDR_W)}000'
            BaseAddr_acc = f'{to_signed_nbit_binary(BaseAddr_acc, BASEADDR_W)}000'
            BaseAddr_weight = f'{to_signed_nbit_binary(BaseAddr_weight, BASEADDR_W)}000'
            machine_code = f'{BaseAddr_dest}_{BaseAddr_source}_{BaseAddr_acc}_{BaseAddr_weight}_000000_{opcode}\n'
            expected_output = f'{BaseAddr_dest}_{BaseAddr_source}_{BaseAddr_acc}_{BaseAddr_weight}_000000_{opcode}\n'
        case "LCCR":
            opcode = '110110'
            BaseAddr_dest = instruction_data[1]
            BaseAddr_source = instruction_data[2]
            BaseAddr_acc = instruction_data[3]
            BaseAddr_weight = instruction_data[4]
            if(BaseAddr_dest[0] == 'A' or BaseAddr_dest[0] == 'B'):
                print("WARNING: destination address cannot be in AB bank")
                return ''
            if(BaseAddr_acc[0] == 'A' or BaseAddr_acc[0] == 'B'):
                print("WARNING: accumulation address cannot be in AB bank")
                return ''
            if(BaseAddr_source[0] == 'C'):
                print("WARNING: source address cannot be in C bank")
                return ''
            if(BaseAddr_weight[0] == 'C'):
                print("WARNING: weight address cannot be in C bank")
                return ''
            BaseAddr_dest = int(BaseAddr_dest[1:])
            BaseAddr_source = int(BaseAddr_source[1:])
            BaseAddr_acc = int(BaseAddr_acc[1:])
            BaseAddr_weight = int(BaseAddr_weight[1:])
            if(BaseAddr_dest < 0 or BaseAddr_dest > 3 or BaseAddr_source < 0 or BaseAddr_source > 3 or BaseAddr_acc < 0 or BaseAddr_acc > 3 or BaseAddr_weight < 0 or BaseAddr_weight > 3):
                print("WARNING: Address out of bounds")
                return ''
            BaseAddr_dest = f'{to_signed_nbit_binary(BaseAddr_dest, BASEADDR_W)}000'
            BaseAddr_source = f'{to_signed_nbit_binary(BaseAddr_source, BASEADDR_W)}000'
            BaseAddr_acc = f'{to_signed_nbit_binary(BaseAddr_acc, BASEADDR_W)}000'
            BaseAddr_weight = f'{to_signed_nbit_binary(BaseAddr_weight, BASEADDR_W)}000'
            machine_code = f'{BaseAddr_dest}_{BaseAddr_source}_{BaseAddr_acc}_{BaseAddr_weight}_000000_{opcode}\n'
            expected_output = f'{BaseAddr_dest}_{BaseAddr_source}_{BaseAddr_acc}_{BaseAddr_weight}_000000_{opcode}\n'
        case "LRCC":
            opcode = '111100'
            BaseAddr_dest = instruction_data[1]
            BaseAddr_source = instruction_data[2]
            BaseAddr_acc = instruction_data[3]
            BaseAddr_weight = instruction_data[4]
            if(BaseAddr_dest[0] == 'A' or BaseAddr_dest[0] == 'B'):
                print("WARNING: destination address cannot be in AB bank")
                return ''
            if(BaseAddr_acc[0] == 'A' or BaseAddr_acc[0] == 'B'):
                print("WARNING: accumulation address cannot be in AB bank")
                return ''
            if(BaseAddr_source[0] == 'C'):
                print("WARNING: source address cannot be in C bank")
                return ''
            if(BaseAddr_weight[0] == 'C'):
                print("WARNING: weight address cannot be in C bank")
                return ''
            BaseAddr_dest = int(BaseAddr_dest[1:])
            BaseAddr_source = int(BaseAddr_source[1:])
            BaseAddr_acc = int(BaseAddr_acc[1:])
            BaseAddr_weight = int(BaseAddr_weight[1:])
            if(BaseAddr_dest < 0 or BaseAddr_dest > 3 or BaseAddr_source < 0 or BaseAddr_source > 3 or BaseAddr_acc < 0 or BaseAddr_acc > 3 or BaseAddr_weight < 0 or BaseAddr_weight > 3):
                print("WARNING: Address out of bounds")
                return ''
            BaseAddr_dest = f'{to_signed_nbit_binary(BaseAddr_dest, BASEADDR_W)}000'
            BaseAddr_source = f'{to_signed_nbit_binary(BaseAddr_source, BASEADDR_W)}000'
            BaseAddr_acc = f'{to_signed_nbit_binary(BaseAddr_acc, BASEADDR_W)}000'
            BaseAddr_weight = f'{to_signed_nbit_binary(BaseAddr_weight, BASEADDR_W)}000'
            machine_code = f'{BaseAddr_dest}_{BaseAddr_source}_{BaseAddr_acc}_{BaseAddr_weight}_000000_{opcode}\n'
            expected_output = f'{BaseAddr_dest}_{BaseAddr_source}_{BaseAddr_acc}_{BaseAddr_weight}_000000_{opcode}\n'
        case "LCCC":
            opcode = '110100'
            BaseAddr_dest = instruction_data[1]
            BaseAddr_source = instruction_data[2]
            BaseAddr_acc = instruction_data[3]
            BaseAddr_weight = instruction_data[4]
            if(BaseAddr_dest[0] == 'A' or BaseAddr_dest[0] == 'B'):
                print("WARNING: destination address cannot be in AB bank")
                return ''
            if(BaseAddr_acc[0] == 'A' or BaseAddr_acc[0] == 'B'):
                print("WARNING: accumulation address cannot be in AB bank")
                return ''
            if(BaseAddr_source[0] == 'C'):
                print("WARNING: source address cannot be in C bank")
                return ''
            if(BaseAddr_weight[0] == 'C'):
                print("WARNING: weight address cannot be in C bank")
                return ''
            BaseAddr_dest = int(BaseAddr_dest[1:])
            BaseAddr_source = int(BaseAddr_source[1:])
            BaseAddr_acc = int(BaseAddr_acc[1:])
            BaseAddr_weight = int(BaseAddr_weight[1:])
            if(BaseAddr_dest < 0 or BaseAddr_dest > 3 or BaseAddr_source < 0 or BaseAddr_source > 3 or BaseAddr_acc < 0 or BaseAddr_acc > 3 or BaseAddr_weight < 0 or BaseAddr_weight > 3):
                print("WARNING: Address out of bounds")
                return ''
            BaseAddr_dest = f'{to_signed_nbit_binary(BaseAddr_dest, BASEADDR_W)}000'
            BaseAddr_source = f'{to_signed_nbit_binary(BaseAddr_source, BASEADDR_W)}000'
            BaseAddr_acc = f'{to_signed_nbit_binary(BaseAddr_acc, BASEADDR_W)}000'
            BaseAddr_weight = f'{to_signed_nbit_binary(BaseAddr_weight, BASEADDR_W)}000'
            machine_code = f'{BaseAddr_dest}_{BaseAddr_source}_{BaseAddr_acc}_{BaseAddr_weight}_000000_{opcode}\n'
            expected_output = f'{BaseAddr_dest}_{BaseAddr_source}_{BaseAddr_acc}_{BaseAddr_weight}_000000_{opcode}\n'
        case _:
            machine_code = ''
    return machine_code

print(to_machine_code("NOOP"))
print(to_machine_code("WRITE8 A1 [1, 2, 3, 4, 5, 6, 7, 8]"))
print(to_machine_code("WRITE8 C1 [1, 2, 3, 4, 5, 6, 7, 8]")) # will throw a warning (wrong bank)
print(to_machine_code("WRITE32 A3 [1, 2, 3, 4, 5, 6, 7, 8]")) # will throw a warning (wrong bank)
print(to_machine_code("WRITE32 C3 [1, 2, 3, 4, 5, 6, 7, 8]")) 
print(to_machine_code("TRANSPOSE A5 B7")) # will throw a warning (address out of bounds)
print(to_machine_code("TRANSPOSE A1 A2"))
print(to_machine_code("WRITE_CSR 00000000_00000000_11111111_00000000_00000000_00000000_11111111_00000000"))
print(to_machine_code("ERROR_CSR"))
print(to_machine_code("READ_CSR"))
print(to_machine_code("READM8 A4")) # will throw a warning (address out of bounds)
print(to_machine_code("READM32 C0"))
print(to_machine_code("READV8 A4")) 
print(to_machine_code("READV32 B31")) # will throw a warning (wrong bank)
print(to_machine_code("LR B3"))
print(to_machine_code("LC C4")) # will throw a warning (address out of bounds)
print(to_machine_code("CR C1 B2 C3")) 
print(to_machine_code("CC A1 B0 C0")) # will throw a warning (wrong bank)
print(to_machine_code("LRCR C3 B1 A1 C0")) # will throw a warning (wrong bank)
print(to_machine_code("LCCR C3 B1 C0 A1"))
print(to_machine_code("LRCC C0 A1 C2 B3"))
print(to_machine_code("LCCC C1 A2 C3 B4")) # will throw a warning (address out of bounds)


# def to_machine_code(instruction):
#     space_i = instruction.find(' ')
#     op = instruction[:space_i] if space_i > 0 else instruction
#     instruction_data =''
#     if(space_i > 0):
#         instruction_data = instruction[space_i+1:]
#     match op:
#         case "WRITE":
#             opcode = '00001'
#             space_i = instruction_data.find(' ')
#             Addr = f'{to_signed_nbit_binary(int(instruction_data[:space_i]), 10)}'
#             data = instruction_data[space_i+2:len(instruction_data)-1].split(sep=', ')
#             data = [f'_{to_signed_nbit_binary(int(n), 8)}' for n in data]
#             data_string = ''
#             for n in data:
#                 data_string += n
#             parity = False
#             for bit in data_string:
#                 if bit == '1':
#                     parity = not parity
#             return f'{opcode}_{Addr}_{int(parity)}{data_string}\n'
#         case "READM8":
#             opcode = '00010'
#             BaseAddr = f'{to_signed_nbit_binary(int(instruction_data), 6)}'
#             return f'{opcode}_{BaseAddr}_00000\n'
#         case "READM8":
#             opcode = '00011'
#             BaseAddr = f'{to_signed_nbit_binary(int(instruction_data), 6)}'
#             return f'{opcode}_{BaseAddr}_00000\n'
#         case "READV8":
#             opcode = '00100'
#             Addr = to_signed_nbit_binary(int(instruction_data), 10)
#             return f'{opcode}_{Addr}_0\n'
#         case "READV16":
#             opcode = '00101'
#             Addr = to_signed_nbit_binary(int(instruction_data), 10)
#             return f'{opcode}_{Addr}_0\n'
#         case "LOADB_ROW":
#             opcode = '00110'
#             BaseAddr = f'{to_signed_nbit_binary(int(instruction_data), 6)}'
#             return f'{opcode}_{BaseAddr}_00000\n'
#         case "LOADB_COL":
#             opcode = '00111'
#             BaseAddr = f'{to_signed_nbit_binary(int(instruction_data), 6)}'
#             return f'{opcode}_{BaseAddr}_00000\n'
#         case "TRANSPOSE":
#             opcode = '01000'
#             instruction_data = instruction_data.split()
#             BaseAddr_source = f'{to_signed_nbit_binary(int(instruction_data[0]), 6)}'
#             BaseAddr_dest = f'{to_signed_nbit_binary(int(instruction_data[1]), 6)}'
#             return f'{opcode}_{BaseAddr_source}_00000_00000_{BaseAddr_dest}_00000'
#         case "COMPUTE_ROW":
#             opcode = '10000'
#             instruction_data = instruction_data.split()
#             BaseAddr_source = f'{to_signed_nbit_binary(int(instruction_data[0]), 6)}'
#             BaseAddr_acc    = f'{to_signed_nbit_binary(int(instruction_data[1]), 6)}'
#             BaseAddr_dest   = f'{to_signed_nbit_binary(int(instruction_data[2]), 6)}'
#             UseAcc = int(instruction_data[3])
#             return f'{opcode}_{BaseAddr_source}_{BaseAddr_acc}_{BaseAddr_dest}_{UseAcc}_00000000\n'
#         case "WRITET":
#             opcode = '00111'
#             instruction_data = instruction_data.split()
#             BaseAddr = instruction_data[0]
#             BaseAddr = f'{to_signed_nbit_binary(int(BaseAddr), 6)}'
#             DestAddr = instruction_data[1]
#             DestAddr = f'{to_signed_nbit_binary(int(DestAddr), 6)}'
#             return f'{opcode}_{BaseAddr}_{DestAddr}_000000000000000\n'
#         case "ERROR":
#             opcode = '11111'
#             return f'{opcode}_00000000000\n'
#         case "NOOP":
#             opcode = '00000'
#             return f'{opcode}_00000000000\n'




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
