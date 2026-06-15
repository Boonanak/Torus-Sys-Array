set _TOP chip_top
set_io_flow_flag 0
create_floorplan -site core7T -core_size 1615 1615 60 60 60 60
read_io_file ../../cfg/chip_top_64_pins.io
add_io_fillers -cells PFILLER0005 PFILLER05 PFILLER1 PFILLER10 PFILLER5 -prefix IO_FILLER
write_io_file -locations ${_TOP}_pins_locations.io
python3 ../../cfg/place_pads.py
read_io_file ${_TOP}_pins_pads.io

set temp_pad [get_db insts -if {.base_cell.name==PV*}]

set pinDict [dict create]
set temp_pad_unique []
foreach pad $temp_pad {
    set pad_inst_name [get_db $pad .name]
    set pad_pin_name [lindex [split $pad_inst_name '_'] 3]
    if { ! [dict exists $pinDict $pad_pin_name] } {
        dict set pinDict $pad_pin_name 0
        lappend temp_pad_unique $pad
    }
}

# print 
foreach pad $temp_pad_unique {
    puts "pad name: $pad"
}

foreach pad $temp_pad_unique {
    set pad_inst_name [get_db $pad .name]
    set pad_pin_name [lindex [split $pad_inst_name '_'] 3]
    #set pad_pin_loc [get_transform_shapes -local_pt {15 71.5} -inst inst:$pad_inst_name]
    set pad_pin_loc [get_transform_shapes -local_pt {30 2.8} -inst inst:$pad_inst_name]
    set pad_x [lindex $pad_pin_loc 0]
    set pad_y [lindex $pad_pin_loc 1]
    set pad_pin_rect [concat $pad_x $pad_y [expr $pad_x + 0.1] [expr $pad_y + 0.1]]
    #create_pg_pin -name $pad_pin_name -net $pad_pin_name -geometry METAL6 [lindex $pad_pin_rect 0] [lindex $pad_pin_rect 1] [lindex $pad_pin_rect 2] [lindex #$pad_pin_rect 3]
    create_pg_pin -name $pad_pin_name -net $pad_pin_name -geometry METAL4 [lindex $pad_pin_rect 0] [lindex $pad_pin_rect 1] [lindex $pad_pin_rect 2] [lindex #$pad_pin_rect 3]
}
# create_pg_pin -name POC -net POC -geometry METAL4 824.02 1962.03 824.12 1962.13 
source ../../cfg/power.tcl