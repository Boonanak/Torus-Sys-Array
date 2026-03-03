# Code to generate trace files

def write_trace(file_name):
    index = 0
    tb_type = ''
    with open(file_name, 'r') as file, open('trace.tr', 'a') as trace:
        for line in file:
            print(line, 'g')
            if(index == 0):
                tb_type = line
                print(tb_type)
            else:
                print('parsing')
                match tb_type:
                    case "PE\n":
                        trace.write(parse_PE_line(line))
                        print(parse_PE_line(line))
                    case "TU":
                        trace.write(parse_TU_line(line))
                    case "ARR":
                        trace.write(parse_ARR_line(line))
                    case "TPU":
                        trace.write(parse_TPU_line(line))
                    case _:
                        trace.write("")
            index = index + 1
            print(index)

def parse_PE_line(PE_line):
    return PE_line

def parse_TU_line(TU_line):
    return TU_line

def parse_ARR_line(ARR_line):
    return ARR_line

def parse_TPU_line(TPU_line):
    return TPU_line

write_trace('PE_test.txt')

print('hello')