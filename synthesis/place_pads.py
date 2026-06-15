import os

# Change top_module here
top_module = 'chip_top'

pin_locations = top_module + '_pins_locations.io'

pins_file = open(pin_locations)

pins_array = []

offset_add = 5
direction = -1

for line in pins_file:
    pins_array.append(line)
    
    if "inst  name" in line and "offset" in line and "Pad_" in line:
        name_begin = line.index("inst  name") + 12
        quote_end = line.rfind("\"")
        offset_begin = line.index("offset") + 7
        offset_end = line.index(" place_")
        
        new_pad = "PAD_" + line[name_begin:quote_end]
        
        offset = float(line[offset_begin:offset_end]) + 5
        
        new_place = "\t(inst  name=\"" + new_pad + "\" cell=\"PAD50LAU_TRL\"  offset=" + str(offset) + ")"
                
        pins_array.append(new_place)

pins_file.close()

pins_pads_locations = top_module + '_pins_pads.io'

pins_pads_file = open(pins_pads_locations, 'w')

for line in pins_array:
    print(line, file=pins_pads_file, end='')  # Changed this line
    
pins_pads_file.close()