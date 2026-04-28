# Code to generate trace files

FLIT_SIZE = 32
NUM_FLITS = 4

def write_trace(input_file_name, trace_file_name, trace_file_name_2 = ''):
    index = 0
    tb_type = ''

    if (trace_file_name_2 != ''):
        with open(input_file_name, 'r') as file, open(trace_file_name, 'w') as trace_send, open(trace_file_name_2, 'w') as trace_recv:
            for line in file:
                line = line.rstrip()
                if(index == 0):
                    tb_type = line
                else:
                    match tb_type:
                        case "ARR":
                            trace_lines = parse_ARR_2_line(line)
                        case "TU":
                            trace_lines = parse_TU_2_line(line)
                        case "PM":
                            trace_lines = parse_PM_line(line)
                        case "DP":
                            trace_lines = parse_DP_line(line)
                    trace_send.write(trace_lines[0])
                    trace_recv.write(trace_lines[1])
                index = index + 1
            return

    with open(input_file_name, 'r') as file, open(trace_file_name, 'w') as trace:
        for line in file:
            line = line.rstrip()
            if(index == 0):
                tb_type = line
            else:
                match tb_type:
                    case "PE":
                        trace.write(parse_PE_line(line))
                    case "PE_final":
                        trace.write(parse_PE_final_line(line))
                    case "DFF":
                        trace.write(parse_DFF_line(line))
                    case "SR":
                        trace.write(parse_SR_line(line))
                    case "CSR":
                        trace.write(parse_CSR_line(line))
                    case "TP_node":
                        trace.write(parse_TP_node_line(line))
                    case "TU":
                        trace.write(parse_TU_line(line))
                    case "ARR":
                        trace.write(parse_ARR_line(line))
                    case "TPU":
                        trace.write(parse_TPU_line(line))
                    case "pipette_pe":
                        trace.write(parse_pipette_pe_line(line))
                    case _:
                        trace.write("")
            index = index + 1

def parse_pipette_pe_line(line):
    space_i = line.find(' ')
    command = line[:space_i].casefold() if space_i > 0 else line.casefold()
    trace_line = ''
    
    # Define bit-width constants for pipette_pe
    # Total bits: 4 (opcode) + 1 (R) + 16 (A) + 8 (B) + 16 (PS) + 3 (Control) = 48 bits
    
    match command:
        case 'load':
            parts = line[space_i:].split()
            major = 1 if parts[0].upper() == 'R' else 0
            A, B, PS = int(parts[1]), int(parts[2]), int(parts[3])
            A_en, B_en, ALP = parts[4], parts[5], parts[6] # 0/1 signals
            
            trace_line += f"# SEND | R={major} | A={A} | B={B} | PS={PS} | Ctrl={A_en}{B_en}{ALP}\n"
            trace_line += f"0001_____{major}{A_en}{B_en}{ALP}_____{to_signed_nbit_binary(A, 16)}_____{to_signed_nbit_binary(B, 8)}_____{to_signed_nbit_binary(PS, 16)}\n"
            
        case 'recv':
            parts = line[space_i:].split()
            major = 1 if parts[0].upper() == 'R' else 0
            A, B, PS = int(parts[1]), int(parts[2]), int(parts[3])
            ALP = parts[4] # Only ActiveLockPulse relevant for recv
            
            trace_line += f"# RECV | R={major} | A={A} | B={B} | PS={PS} | ALP={ALP}\n"
            # Zero out A_en and B_en (first two control bits) as they aren't cared about in recv
            if (major) :
                trace_line += f"0010_____000{ALP}_____{to_signed_nbit_binary(A, 16)}_____{to_signed_nbit_binary(B, 8)}_____{to_signed_nbit_binary(PS, 16)}\n"
            else:
                trace_line += f"0010_____000{ALP}_____{to_signed_nbit_binary(PS, 16)}_____{to_signed_nbit_binary(B, 8)}_____{to_signed_nbit_binary(A, 16)}\n"
        case 'wait':
            n = int(line[space_i:])
            trace_line += f"# WAIT for {n} cycles\n"
            for _ in range(n):
                trace_line += f"0000_____{'0'*44}\n"
                
        case 'end':
            trace_line += f"# ENDING SIMULATION\n0100_____{'0'*44}\n"
            
        case '###':
            trace_line += line

    return trace_line + '\n'

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
                trace_line += f"0000__{'0'*25}\n"
        case 'end':
            trace_line += f"# ENDING SIMULATION\n0100__{'0'*25}\n"
        case '###':
            trace_line += PE_line
    return trace_line + '\n'

def parse_PE_final_line(PE_line):
    space_i = PE_line.find(' ')
    command = PE_line[:space_i] if space_i > 0 else PE_line
    trace_line = ''
    match command.casefold():
        case 'load':
            PE_line = PE_line[space_i+1:]
            space_i = PE_line.find(' ')
            major = True if PE_line[:space_i] == 'R' else False
            B_in = int(PE_line[space_i:])
            B_in_trace = f"00000000_{to_signed_nbit_binary(B_in, 8)}"
            other_trace = '00000000_00000000'
            trace_line += f"# SEND  |  load_B  |  {'row major' if major else 'col major'}  |  B = {B_in}\n"
            trace_line += f"0001______1______{int(major)}______{B_in_trace if major else other_trace}______{other_trace if major else B_in_trace}\n"
        case 'compute':
            PE_line = PE_line[space_i+1:]
            space_i = PE_line.find(' ')
            major = True if PE_line[:space_i] == 'R' else False
            numbers = [int(n) for n in PE_line[space_i:].split()]
            A_in = numbers[0]
            A_in_trace = f"00000000_{to_signed_nbit_binary(A_in, 8)}"
            PS_in = numbers[1]
            PS_in_trace = f"{to_signed_nbit_binary(PS_in, 16)}"
            trace_line += f"# SEND  |  compute |  {'row major' if major else 'col major'}  |  A = {A_in}  |  PS = {PS_in}\n"
            trace_line += f"0001______0______{int(major)}______{A_in_trace if major else PS_in_trace}______{PS_in_trace if major else A_in_trace}\n"
        case 'recv':
            PE_line = PE_line[space_i+1:]
            space_i = PE_line.find(' ')
            major = True if PE_line[:space_i] == 'R' else False
            numbers = [int(n) for n in PE_line[space_i:].split()]
            A_out = numbers[0]
            A_out_trace = f"00000000_{to_signed_nbit_binary(A_out, 8)}"
            PS_out = numbers[1]
            PS_out_trace = f"{to_signed_nbit_binary(PS_out, 16)}"
            trace_line += f"# RECV  |  A = {A_out}  |  PS = {PS_out}\n"
            trace_line += f"0010______0______0______{A_out_trace if major else PS_out_trace}______{PS_out_trace if major else A_out_trace}\n"
        case 'wait':
            n = int(PE_line[space_i:])
            trace_line += f"# WAIT for {n} cycles\n"
            for i in range(n):
                trace_line += f"0000__{'0'*34}\n"
        case 'end':
            trace_line += f"# ENDING SIMULATION\n0100__{'0'*34}\n"
        case '###':
            trace_line += PE_line
    return trace_line + '\n'

def parse_DFF_line(DFF_line):
    space_i = DFF_line.find(' ')
    command = DFF_line[:space_i] if space_i > 0 else DFF_line
    trace_line = ''
    match command.casefold():
        case 'load':
            numbers = [int(n) for n in DFF_line[space_i:].split()]
            en = numbers[0]
            d = numbers[1]
            trace_line += f"# SEND  | en={en} |   D = {d}\n"
            trace_line += f"0001_____{en}_______{to_signed_nbit_binary(d, 8)}\n"
        case 'recv':
            q = int(DFF_line[space_i:])
            trace_line += f"# RECV  |   Q = {q}\n"
            trace_line += f"0010_____0_______{to_signed_nbit_binary(q, 8)}\n"
        case 'wait':
            n = int(DFF_line[space_i:])
            trace_line += f"# WAIT for {n} cycles\n"
            for i in range(n):
                trace_line += f"0000__{'0'*9}\n"
        case 'end':
            trace_line += f"# ENDING SIMULATION\n0100__{'0'*9}\n"
        case '###':
            trace_line += DFF_line
    return trace_line + '\n'

def parse_SR_line(SR_line):
    space_i = SR_line.find(' ')
    command = SR_line[:space_i] if space_i > 0 else SR_line
    trace_line = ''
    match command.casefold():
        case 'load':
            numbers = [int(n) for n in SR_line[space_i:].split()]
            write = numbers[0]
            read = numbers[1]
            data_i = numbers[2]
            trace_line += f"# SEND  | write={write} | read={read} | data = {data_i}\n"
            trace_line += f"0001______{write}____{read}_______{'_00000000'*7}_{to_signed_nbit_binary(data_i, 8)}\n"
        case 'recv':
            numbers = [int(n) for n in SR_line[space_i:].split()]
            full = numbers[0]
            empty = numbers[1]
            numbers = numbers[2:]
            trace_line += f"# RECV  | full={full} | empty={empty} | data = {numbers}\n"
            trace_line += f"0010______{full}____{empty}_______"
            for n in numbers:
                trace_line += f"_{to_signed_nbit_binary(n, 8)}"
            trace_line += '\n'
        case 'wait':
            n = int(SR_line[space_i:])
            trace_line += f"# WAIT for {n} cycles\n"
            for i in range(n):
                trace_line += f"0000__{'0'*66}\n"
        case 'end':
            trace_line += f"# ENDING SIMULATION\n0100__{'0'*66}\n"
        case '###':
            trace_line += SR_line
    return trace_line + '\n'

def parse_CSR_line(SR_line):
    space_i = SR_line.find(' ')
    command = SR_line[:space_i] if space_i > 0 else SR_line
    trace_line = ''
    match command.casefold():
        case 'read':
            data = SR_line[space_i+1:]
            trace_line += f"# RECV | data = {data}\n"
            trace_line += f"0010________00____{data}\n"
        case 'set':
            bits = [int(n) for n in SR_line[space_i:].split()]
            mask = f'{'0'*64}'
            for bit in bits:
                mask = list(mask)
                mask[63-bit] = '1'
                mask = "".join(mask)
            trace_line += f"# SEND | mode = SET | bits = {bits}\n"
            trace_line += f"0001________01____{mask}\n"
        case 'clear':
            bits = [int(n) for n in SR_line[space_i:].split()]
            mask = f'{'0'*64}'
            for bit in bits:
                mask = list(mask)
                mask[63-bit] = '1'
                mask = "".join(mask)
            trace_line += f"# SEND | mode = CLEAR | bits = {bits}\n"
            trace_line += f"0001________10____{mask}\n"
        case 'clearall':
            mask = f'{'1'*64}'
            trace_line += f"# SEND | mode = CLEAR | bits = [63:0]\n"
            trace_line += f"0001________10____{mask}\n"
        case 'assign':
            data = SR_line[space_i+1:]
            trace_line += f"# SEND | mode = ASSIGN | data = {data}\n"
            trace_line += f"0001________11____{data}\n"
        case 'wait':
            n = int(SR_line[space_i:])
            trace_line += f"# WAIT for {n} cycles\n"
            for i in range(n):
                trace_line += f"0000__{'0'*66}\n"
        case 'end':
            trace_line += f"# ENDING SIMULATION\n0100__{'0'*66}\n"
        case '###':
            trace_line += SR_line
    return trace_line + '\n'

def parse_PM_line(MEM_line):
    space_i = MEM_line.find(' ')
    command = MEM_line[:space_i] if space_i > 0 else MEM_line
    instruction_data = MEM_line[space_i:].split() if space_i > 0 else ''
    trace_line_send = ''
    trace_line_recv = ''
    NOOP = f'0000_00_000000_000000{'_00000000'*16}\n'
    match command.casefold():
        case 'read':
            wr_en = f'_00'
            write_addr = f'_000000'
            read_addr = f'_{to_signed_nbit_binary(int(instruction_data[0]), 6)}'
            write_data = f'{'_00000000'*16}'
            trace_line_send += f'0001{wr_en}{write_addr}{read_addr}{write_data}'
            trace_line_recv += NOOP
        case 'write':
            wr_en = f'_{instruction_data[0]}'
            write_addr = f'_{to_signed_nbit_binary(int(instruction_data[1]), 6)}'
            read_addr = f'_000000'
            write_data = [int(n) for n in instruction_data[2:18]]
            write_data_string = ''
            for data in write_data:
                write_data_string += f'_{to_signed_nbit_binary(data, 8)}'
            write_data = write_data_string
            trace_line_send += f'0001{wr_en}{write_addr}{read_addr}{write_data}'
            trace_line_recv += NOOP
        case 'read_write':
            wr_en = f'_{instruction_data[0]}'
            write_addr = f'_{to_signed_nbit_binary(int(instruction_data[1]), 6)}'
            read_addr = f'_{to_signed_nbit_binary(int(instruction_data[2]), 6)}'
            write_data = [int(n) for n in instruction_data[3:19]]
            write_data_string = ''
            for data in write_data:
                write_data_string += f'_{to_signed_nbit_binary(data, 8)}'
            write_data = write_data_string
            trace_line_send += f'0001{wr_en}{write_addr}{read_addr}{write_data}'
            trace_line_recv += NOOP
        case 'recv':
            trace_line_send += NOOP
            read_data = [int(n) for n in instruction_data[0:16]]
            read_data_string = ''
            for data in read_data:
                read_data_string += f'_{to_signed_nbit_binary(data, 8)}'
            trace_line_recv += f'0010_00_000000_000000{read_data_string}'
        case 'read_recv':
            wr_en = f'_00'
            write_addr = f'_000000'
            read_addr = f'_{to_signed_nbit_binary(int(instruction_data[0]), 6)}'
            write_data = f'{'_00000000'*16}'
            trace_line_send += f'0001{wr_en}{write_addr}{read_addr}{write_data}'
            read_data = [int(n) for n in instruction_data[1:17]]
            read_data_string = ''
            for data in read_data:
                read_data_string += f'_{to_signed_nbit_binary(data, 8)}'
            trace_line_recv += f'0010_00_000000_000000{read_data_string}'
        case 'write_recv':
            wr_en = f'_{instruction_data[0]}'
            write_addr = f'_{to_signed_nbit_binary(int(instruction_data[1]), 6)}'
            read_addr = f'_000000'
            write_data = [int(n) for n in instruction_data[2:18]]
            write_data_string = ''
            for data in write_data:
                write_data_string += f'_{to_signed_nbit_binary(data, 8)}'
            write_data = write_data_string
            trace_line_send += f'0001{wr_en}{write_addr}{read_addr}{write_data}'
            read_data = [int(n) for n in instruction_data[18:34]]
            read_data_string = ''
            for data in read_data:
                read_data_string += f'_{to_signed_nbit_binary(data, 8)}'
            trace_line_recv += f'0010_00_000000_000000{read_data_string}'
        case 'read_write_recv':
            wr_en = f'_{instruction_data[0]}'
            write_addr = f'_{to_signed_nbit_binary(int(instruction_data[1]), 6)}'
            read_addr = f'_{to_signed_nbit_binary(int(instruction_data[2]), 6)}'
            write_data = [int(n) for n in instruction_data[3:19]]
            write_data_string = ''
            for data in write_data:
                write_data_string += f'_{to_signed_nbit_binary(data, 8)}'
            write_data = write_data_string
            trace_line_send += f'0001{wr_en}{write_addr}{read_addr}{write_data}'
            read_data = [int(n) for n in instruction_data[19:35]]
            read_data_string = ''
            for data in read_data:
                read_data_string += f'_{to_signed_nbit_binary(data, 8)}'
            trace_line_recv += f'0010_00_000000_000000{read_data_string}'
        case 'wait':
            n = int(instruction_data[0])
            for i in range(n):
                trace_line_send += NOOP
                trace_line_recv += NOOP
        case 'end':
            trace_line_send += f"0100_00_000000_000000_{'_00000000'*16}\n"
            trace_line_recv += f"0100_00_000000_000000_{'_00000000'*16}\n"
        case '###':
            trace_line_send += MEM_line
            trace_line_recv += MEM_line
    return trace_line_send + '\n', trace_line_recv + '\n'

def parse_TP_node_line(TU_line):
    space_i = TU_line.find(' ')
    command = TU_line[:space_i] if space_i > 0 else TU_line
    trace_line = ''
    match command.casefold():
        case 'load':
            numbers = [int(n) for n in TU_line[space_i:].split()]
            row = numbers[0]
            col = numbers[1]
            direction = numbers[2]
            counter = numbers[3]
            trace_line += f"# SEND  |  NODE ({row}, {col})  |  counter = {counter}  |  inputs = {numbers[4:]}\n"
            trace_line += f"0001______{to_signed_nbit_binary(row, 4)[1:]}_{to_signed_nbit_binary(col, 4)[1:]}______1______{direction}{to_signed_nbit_binary(counter, 4)[1:]}_____"
            for n in numbers[4:]:
                trace_line += f"_{to_signed_nbit_binary(n, 8)}"
            trace_line += '\n'
        case 'recv':
            numbers = [int(n) for n in TU_line[space_i:].split()]
            row = numbers[0]
            col = numbers[1]
            data = numbers[2]
            trace_line += f"# RECV  |  NODE ({row}, {col})  |  data = {data}\n"
            trace_line += f"0010______{to_signed_nbit_binary(row, 4)[1:]}_{to_signed_nbit_binary(col, 4)[1:]}______0______0000______00000000_00000000_00000000_{to_signed_nbit_binary(data, 8)}\n"
        case 'wait':
            n = int(TU_line[space_i:])
            trace_line += f"# WAIT for {n} cycles\n"
            for i in range(n):
                trace_line += f"0000__{'0'*43}\n"
        case 'end':
            trace_line += f"# ENDING SIMULATION\n0100__{'0'*43}\n"
        case '###':
            trace_line += TU_line
    return trace_line + '\n'

def parse_TU_line(TU_line):
    space_i = TU_line.find(' ')
    command = TU_line[:space_i] if space_i > 0 else TU_line
    trace_line = ''
    match command.casefold():
        case 'load':
            numbers = [int(n) for n in TU_line[space_i:].split()]
            trace_line += f"# SEND  |  {numbers}\n"
            trace_line += f"0001_________"
            for n in numbers:
                trace_line += f"_{to_signed_nbit_binary(n, 8)}"
            trace_line += '\n'
        case 'recv':
            numbers = [int(n) for n in TU_line[space_i:].split()]
            trace_line += f"# RECV  |  {numbers}\n"
            trace_line += f"0010_________"
            for n in numbers:
                trace_line += f"_{to_signed_nbit_binary(n, 8)}"
            trace_line += '\n'
        case 'wait':
            n = int(TU_line[space_i:])
            trace_line += f"# WAIT for {n} cycles\n"
            for i in range(n):
                trace_line += f"0000__{'0'*32}\n"
        case 'end':
            trace_line += f"# ENDING SIMULATION\n0100__{'0'*32}\n"
        case '###':
            trace_line += TU_line
    return trace_line + '\n'

def parse_TU_2_line(TU_line):
    MATRIX_SIZE = 8
    space_i = TU_line.find(' ')
    command = TU_line[:space_i] if space_i > 0 else TU_line
    trace_line_send = ''
    trace_line_recv = ''
    #print(f'_{command.casefold()}_')
    match command.casefold():
        case 'load':
            numbers = [int(n) for n in TU_line[space_i:].split()]
            trace_line_send += f"# LOAD  |  {numbers}\n"
            trace_line_send += f"0001_______0___"
            for n in numbers:
                trace_line_send += f"_{to_signed_nbit_binary(n, 8)}"
            trace_line_send += '\n'
            trace_line_recv += f"# NOOP for RECV while loading B\n0000_______0____{'0'*8*MATRIX_SIZE}\n"
        case 'recv':
            numbers = [int(n) for n in TU_line[space_i:].split()]
            trace_line_recv += f"# RECV (passed)  |  {numbers}\n"
            trace_line_recv += f"0010_______0___"
            for n in numbers:
                trace_line_recv += f"_{to_signed_nbit_binary(n, 8)}"
            trace_line_recv += '\n'
            trace_line_send += f"# Receiving with no transpose; T = 0\n0000_______0____{'0'*8*MATRIX_SIZE}\n"
        case 'recvt':
            numbers = [int(n) for n in TU_line[space_i:].split()]
            trace_line_recv += f"# RECV (transposed)  |  {numbers}\n"
            trace_line_recv += f"0010_______0___"
            for n in numbers:
                trace_line_recv += f"_{to_signed_nbit_binary(n, 8)}"
            trace_line_recv += '\n'
            trace_line_send += f"# Receiving with transpose; T = 1\n0000_______1____{'0'*8*MATRIX_SIZE}\n"
        case 'load_recv':
            numbers = [int(n) for n in TU_line[space_i:].split()]
            trace_line_send += f"# LOAD  |  {numbers[:8]}  |  Receiving with no transpose; T = 0\n"
            trace_line_send += f"0001_______0___"
            for n in numbers[:MATRIX_SIZE]:
                trace_line_send += f"_{to_signed_nbit_binary(n, 8)}"
            trace_line_send += '\n'
            trace_line_recv += f"# RECV  |  {numbers[8:]}\n"
            trace_line_recv += f"0010_______0___"
            for n in numbers[MATRIX_SIZE:]:
                trace_line_recv += f"_{to_signed_nbit_binary(n, 8)}"
            trace_line_recv += '\n'
        case 'load_recvt':
            numbers = [int(n) for n in TU_line[space_i:].split()]
            trace_line_send += f"# LOAD  |  {numbers[:8]}  |  Receiving with transpose; T = 1\n"
            trace_line_send += f"0001_______1___"
            for n in numbers[:MATRIX_SIZE]:
                trace_line_send += f"_{to_signed_nbit_binary(n, 8)}"
            trace_line_send += '\n'
            trace_line_recv += f"# RECV  |  {numbers[8:]}\n"
            trace_line_recv += f"0010_______0___"
            for n in numbers[MATRIX_SIZE:]:
                trace_line_recv += f"_{to_signed_nbit_binary(n, 8)}"
            trace_line_recv += '\n'
        case 'wait':
            n = int(TU_line[space_i:])
            trace_line_send += f"# WAIT for {n} cycles\n"
            for i in range(n):
                trace_line_send += f"0000_______0____{'0'*8*MATRIX_SIZE}\n"
            trace_line_recv += f"# WAIT for {n} cycles\n"
            for i in range(n):
                trace_line_recv += f"0000_______0____{'0'*8*MATRIX_SIZE}\n"
        case 'end':
            trace_line_send += f"# ENDING SIMULATION\n0100_______0____{'0'*8*MATRIX_SIZE}\n"
            trace_line_recv += f"# ENDING SIMULATION\n0100_______0____{'0'*8*MATRIX_SIZE}\n"
        case '###':
            trace_line_send += TU_line
            trace_line_recv += TU_line
    return trace_line_send + '\n', trace_line_recv + '\n'

def parse_ARR_line(ARR_line):
    space_i = ARR_line.find(' ')
    command = ARR_line[:space_i] if space_i > 0 else ARR_line
    trace_line = ''
    match command.casefold():
        case 'loadb':
            ARR_line = ARR_line[space_i+1:]
            space_i = ARR_line.find(' ')
            major = True if ARR_line[:space_i] == 'R' else False
            numbers = [int(n) for n in ARR_line[space_i:].split()]
            trace_line += f"# SEND  |   1   | {'row maj' if major else 'col maj'} | B[i] = {numbers}\n"
            trace_line += f"0001______1______{int(major)}______{'0'*30}_______"
            for n in numbers:
                trace_line += f"_{to_signed_nbit_binary(n, 8)}"
            trace_line += '\n'
        case 'compute':
            ARR_line = ARR_line[space_i+1:]
            space_i = ARR_line.find(' ')
            major = True if ARR_line[:space_i] == 'R' else False
            numbers = [int(n) for n in ARR_line[space_i:].split()]
            trace_line += f"# SEND  |   0   | {'row maj' if major else 'col maj'} | A[i] = {numbers}\n"
            trace_line += f"0001______0______{int(major)}_____________{'0'*30}_______"
            for n in numbers:
                trace_line += f"_{to_signed_nbit_binary(n, 8)}"
            trace_line += '\n'
        case 'recv':
            numbers = [int(n) for n in ARR_line[space_i:].split()]
            trace_line += f"# RECV  |    00    | C[i] = {numbers}\n"
            trace_line += f"0010_______"
            for n in numbers:
                trace_line += f"_{to_signed_nbit_binary(n, 16)}"
            trace_line += '\n'
        case 'wait':
            n = int(ARR_line[space_i:])
            trace_line += f"# WAIT for {n} cycles\n"
            for i in range(n):
                trace_line += f"0000__{'0'*64}\n"
        case 'end':
            trace_line += f"# ENDING SIMULATION\n0100__{'0'*64}\n"
        case '###':
            trace_line += ARR_line
    return trace_line + '\n'

def parse_ARR_2_line(ARR_line):
    space_i = ARR_line.find(' ')
    command = ARR_line[:space_i] if space_i > 0 else ARR_line
    trace_line_send = ''
    trace_line_recv = ''
    match command.casefold():
        case 'loadb':
            ARR_line = ARR_line[space_i+1:]
            space_i = ARR_line.find(' ')
            major = True if ARR_line[:space_i] == 'R' else False
            numbers = [int(n) for n in ARR_line[space_i:].split()]
            trace_line_send += f"# SEND  |   1   | {'row maj' if major else 'col maj'} | B[i] = {numbers}\n"
            trace_line_send += f"0001______1______{int(major)}______{'0'*30}_______"
            for n in numbers:
                trace_line_send += f"_{to_signed_nbit_binary(n, 8)}"
            trace_line_send += '\n'
            trace_line_recv += f"# NOOP for RECV while loading B\n0000__{'0'*64}\n"
        case 'compute':
            ARR_line = ARR_line[space_i+1:]
            space_i = ARR_line.find(' ')
            major = True if ARR_line[:space_i] == 'R' else False
            numbers = [int(n) for n in ARR_line[space_i:].split()]
            trace_line_send += f"# SEND  |   0   | {'row maj' if major else 'col maj'} | A[i] = {numbers}\n"
            trace_line_send += f"0001______0______{int(major)}_____________{'0'*30}_______"
            for n in numbers:
                trace_line_send += f"_{to_signed_nbit_binary(n, 8)}"
            trace_line_send += '\n'
            trace_line_recv += f"# NOOP for RECV while loading B\n0000__{'0'*64}\n"
        case 'recv':
            numbers = [int(n) for n in ARR_line[space_i:].split()]
            trace_line_recv += f"# RECV  | C[i] = {numbers}\n"
            trace_line_recv += f"0010_______"
            for n in numbers:
                trace_line_recv += f"_{to_signed_nbit_binary(n, 16)}"
            trace_line_recv += '\n'
            trace_line_send += f"# NOOP for SEND while receiving\n0000__{'0'*64}\n"
        case 'loadb_recv':
            ARR_line = ARR_line[space_i+1:]
            space_i = ARR_line.find(' ')
            major = True if ARR_line[:space_i] == 'R' else False
            numbers = [int(n) for n in ARR_line[space_i:].split()]
            trace_line_send += f"# SEND  |   1   | {'row maj' if major else 'col maj'} | B[i] = {numbers[:4]}\n"
            trace_line_send += f"0001______1______{int(major)}______{'0'*30}_______"
            for n in numbers[:4]:
                trace_line_send += f"_{to_signed_nbit_binary(n, 8)}"
            trace_line_send += '\n'
            trace_line_recv += f"# RECV   | C[i] = {numbers[4:]}\n"
            trace_line_recv += f"0010_______"
            for n in numbers[4:]:
                trace_line_recv += f"_{to_signed_nbit_binary(n, 16)}"
            trace_line_recv += '\n'
        case 'compute_recv':
            ARR_line = ARR_line[space_i+1:]
            space_i = ARR_line.find(' ')
            major = True if ARR_line[:space_i] == 'R' else False
            numbers = [int(n) for n in ARR_line[space_i:].split()]
            trace_line_send += f"# SEND  |   0   | {'row maj' if major else 'col maj'} | A[i] = {numbers[:4]}\n"
            trace_line_send += f"0001______0______{int(major)}_____________{'0'*30}_______"
            for n in numbers[:4]:
                trace_line_send += f"_{to_signed_nbit_binary(n, 8)}"
            trace_line_send += '\n'
            trace_line_recv += f"# RECV  | C[i] = {numbers[4:]}\n"
            trace_line_recv += f"0010_______"
            for n in numbers[4:]:
                trace_line_recv += f"_{to_signed_nbit_binary(n, 16)}"
            trace_line_recv += '\n'
        case 'wait':
            n = int(ARR_line[space_i:])
            trace_line_send += f"# WAIT for {n} cycles\n"
            for i in range(n):
                trace_line_send += f"0000__{'0'*64}\n"
            trace_line_recv += f"# WAIT for {n} cycles\n"
            for i in range(n):
                trace_line_recv += f"0000__{'0'*64}\n"
        case 'end':
            trace_line_send += f"# ENDING SIMULATION\n0100__{'0'*64}\n"
            trace_line_recv += f"# ENDING SIMULATION\n0100__{'0'*64}\n"
        case '###':
            trace_line_send += ARR_line
            trace_line_recv += ARR_line
    return trace_line_send + '\n', trace_line_recv + '\n'

def parse_DP_line(DP_line):
    space_i = DP_line.find(' ')
    command = DP_line[:space_i] if space_i > 0 else DP_line
    trace_line_send = ''
    trace_line_recv = ''
    NOOP_send = f'# NOOP\n0000____00_{'0'*FLIT_SIZE*NUM_FLITS}\n'
    NOOP_recv = f'# NOOP\n0000____{'0'*FLIT_SIZE}\n'
    match command.casefold():
        case 'send':
            data_in = DP_line[space_i+1:].strip()
            num_packets = int(len(data_in) / (FLIT_SIZE/4))
            trace_line_send += f'# SEND {int(num_packets)} flits | data = {data_in}\n'
            data_in = bin(int(data_in, 16))[2:]
            data_in = data_in.zfill(FLIT_SIZE*num_packets) + f'{'0'*FLIT_SIZE*(NUM_FLITS-int(num_packets))}'
            num_packets = bin(int(num_packets) - 1)[2:].zfill(2)
            trace_line_send += f'0001____{num_packets}_{data_in}\n'
            trace_line_recv += NOOP_recv
        case 'recv':
            trace_line_send += NOOP_send
            data_out = DP_line[space_i+1:].strip()
            trace_line_recv += f'# RECV | data = {data_out}\n'
            data_out = bin(int(data_out, 16))[2:]
            data_out = data_out.zfill(FLIT_SIZE)
            trace_line_recv += f'0010____{data_out}\n'
        case 'send_recv':
            data = DP_line[space_i:].split()
            data_in = data[0]
            num_packets = len(data_in) / (FLIT_SIZE/4)
            trace_line_send += f'# SEND {int(num_packets)} flits | data = {data_in}\n'
            data_in = bin(int(data_in, 16))[2:]
            data_in = data_in.zfill(FLIT_SIZE * NUM_FLITS)
            num_packets = bin(int(num_packets) - 1)[2:].zfill(2)
            trace_line_send += f'0001____{num_packets}_{data_in}\n'
            data_out = data[1]
            trace_line_recv += f'# RECV | data = {data_out}\n'
            data_out = bin(int(data_out, 16))[2:]
            data_out = data_out.zfill(FLIT_SIZE)
            trace_line_recv += f'0010____{data_out}\n'
        case 'wait':
            n = int(DP_line[space_i:])
            trace_line_send += f"# WAIT for {n} cycles\n"
            for i in range(n):
                trace_line_send += f"0000____00_{'0'*FLIT_SIZE*NUM_FLITS}\n"
            trace_line_recv += f"# WAIT for {n} cycles\n"
            for i in range(n):
                trace_line_recv += f"0000____{'0'*FLIT_SIZE}\n"
        case 'end':
            trace_line_send += f"# ENDING SIMULATION\n0100____00_{'0'*FLIT_SIZE*NUM_FLITS}\n"
            trace_line_recv += f"# ENDING SIMULATION\n0100____{'0'*FLIT_SIZE}\n"
        case '###':
            trace_line_send += DP_line
            trace_line_recv += DP_line
    return trace_line_send + '\n', trace_line_recv + '\n'

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



write_trace('scripts/DP_test_final.txt', 'v/Top_level/depacketizer_send_trace.tr', 'v/Top_level/depacketizer_recv_trace.tr')
# print(parse_DP_line('end')[0])

