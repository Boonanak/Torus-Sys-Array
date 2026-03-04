# Code to generate trace files

def write_trace(file_name):
    index = 0
    tb_type = ''
    with open(file_name, 'r') as file, open('trace.tr', 'w') as trace:
        for line in file:
            line = line.rstrip()
            if(index == 0):
                tb_type = line
            else:
                match tb_type:
                    case "PE":
                        trace.write(parse_PE_line(line))
                    case "SR":
                        trace.write(parse_SR_line(line))
                    case "TU":
                        trace.write(parse_TU_line(line))
                    case "ARR":
                        trace.write(parse_ARR_line(line))
                    case "TPU":
                        trace.write(parse_TPU_line(line))
                    case _:
                        trace.write("")
            index = index + 1

def parse_PE_line(PE_line):
    space_i = PE_line.find(' ')
    command = PE_line[:space_i] if space_i > 0 else PE_line
    trace_line = ''
    match command.casefold():
        case 'load':
            numbers = [int(n) for n in PE_line[space_i:].split()]
            A_in = numbers[0]
            masked = numbers[1]
            B_in = numbers[2]
            trace_line += "# SEND  |  load_B  |" + ("A_in = " + str(A_in)).center(16) + "|" +  ("masked-bits_B_in = " + str(masked) + '_' + str(B_in)).center(24) + '\n'
            trace_line += f"0001______1__________{to_signed_nbit_binary(A_in, 8)}__________{to_signed_nbit_binary(masked, 8)}_{to_signed_nbit_binary(B_in, 8)}\n"
        case 'compute':
            numbers = [int(n) for n in PE_line[space_i:].split()]
            A_in = numbers[0]
            PS_in = numbers[1]
            trace_line += "# SEND  |  compute |" + ("A_in = " + str(A_in)).center(16) + "|" +  ("PS_in = " + str(PS_in)).center(24) + '\n'
            trace_line += f"0001______0__________{to_signed_nbit_binary(A_in, 8)}__________{to_signed_nbit_binary(PS_in, 16)}\n"
        case 'recv':
            numbers = [int(n) for n in PE_line[space_i:].split()]
            A_out = numbers[0]
            shared_B_PS_out = numbers[1]
            trace_line += "# RECV  |     0    |" + ("A_out = " + str(A_out)).center(16) + "|" +  ("shared_B_PS_out = " + str(shared_B_PS_out)).center(24) + '\n'
            trace_line += f"0010______0__________{to_signed_nbit_binary(A_out, 8)}__________{to_signed_nbit_binary(shared_B_PS_out, 16)}\n"
        case 'wait':
            n = int(PE_line[space_i:])
            trace_line += f"# WAIT for {n} cycles\n"
            for i in range(n):
                trace_line += "0000__00000000_00000000_00000000_00000000\n"
        case 'end':
            trace_line += "# ENDING SIMULATION\n0100__0_00000000_00000000_00000000\n"
        case '###':
            trace_line += PE_line
    return trace_line + '\n'

def parse_SR_line(SR_line):
    return SR_line

def parse_TU_line(TU_line):
    space_i = TU_line.find(' ')
    command = TU_line[:space_i] if space_i > 0 else TU_line
    print(command)
    trace_line = ''
    match command.casefold():
        case 'load':
            numbers = [int(n) for n in TU_line[space_i:].split()]
            trace_line += f"# SEND  |  {numbers}\n"
            trace_line += f"0001_________"
            for i in range(12):
                trace_line += "_00000000"
            for n in numbers:
                trace_line += f"_{to_signed_nbit_binary(n, 8)}"
            trace_line += '\n'
        case 'recv':
            numbers = [int(n) for n in TU_line[space_i:].split()]
            trace_line += f"# RECV  |     0    |   {numbers}\n"
            trace_line += f"0010_________"
            for n in numbers:
                trace_line += f"_{to_signed_nbit_binary(n, 8)}"
            trace_line += '\n'
        case 'wait':
            n = int(TU_line[space_i:])
            trace_line += f"# WAIT for {n} cycles\n"
            for i in range(n):
                trace_line += "0000__00000000_00000000_00000000_00000000\n"
        case 'end':
            trace_line += "# ENDING SIMULATION\n0100__0_00000000_00000000_00000000\n"
        case '###':
            trace_line += TU_line
    return trace_line + '\n'

def parse_ARR_line(ARR_line):
    return ARR_line

def parse_TPU_line(TPU_line):
    return TPU_line

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



write_trace('TU_test.txt')
