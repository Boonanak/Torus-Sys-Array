# runlab.do
#
# Usage, in the Questa transcript (forward slashes, even on Windows):
#     cd C:/intelFPGA_lite/17.0/pipette_quartus_new
#     do runlab.do
#
# Compiles every Verilog/SystemVerilog file listed in the Quartus project (.qsf),
# in the project's own order (packages first), then your testbench, then simulates.
# The .qsf is the single list of files, so simulation and synthesis stay in sync.

# ---------------- edit these ----------------
set QSF  "quartus_proj.qsf"     ;# project settings file, relative to the folder you cd'd to
set TB   "emu_top_tb.sv"        ;# testbench file, only if it is NOT already in the .qsf (else "" or any missing name)
set TOP  "emu_top_tb"           ;# testbench module name
set RUN  "50 ms"                 ;# how long to simulate
set PERMISSIVE 1                ;# 1 = pass -permissive to vsim (relaxes some LRM error checks to warnings)
set OVR  "sim_overrides"        ;# folder of simulation-only replacement files (see below)
# --------------------------------------------

quit -sim
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# Pull source files and include folders out of the .qsf
set files {}
set incs  {}
set fp [open $QSF r]
while {[gets $fp line] >= 0} {
    if {[regexp {^set_global_assignment\s+-name\s+(SYSTEMVERILOG_FILE|VERILOG_FILE)\s+"?([^"[:space:]]+)"?} $line -> kind f]} {
        lappend files $f
    } elseif {[regexp {^set_global_assignment\s+-name\s+SEARCH_PATH\s+"?([^"[:space:]]+)"?} $line -> d]} {
        lappend incs "+incdir+$d"
    }
}
close $fp

# Simulation-only overrides: if a file with the same name exists in $OVR, it is
# compiled INSTEAD of the project's copy. Your real source files are never touched.
set final {}
foreach f $files {
    set o [file join $OVR [file tail $f]]
    if {[file exists $o]} {
        puts "runlab: using override $o instead of $f"
        lappend final $o
    } else {
        lappend final $f
    }
}
set files $final
puts "runlab: compiling [llength $files] files from $QSF"

# -sv: treat every file (including .v) as SystemVerilog
vlog -sv -work work {*}$incs {*}$files

# The testbench is compiled here only if the file is found. If it is already in
# the .qsf list (and so was compiled above), or TB points at a wrong path, we skip
# it; vsim below will then fail clearly if $TOP really doesn't exist.
if {$TB ne "" && [file exists $TB]} {
    vlog -sv -work work {*}$incs $TB
} else {
    puts "runlab: '$TB' not found in [pwd]; assuming $TOP was compiled from the .qsf list"
}

set VSIM_EXTRA {}
if {$PERMISSIVE} { lappend VSIM_EXTRA -permissive }
vsim {*}$VSIM_EXTRA -voptargs="+acc" -t 1ps -lib work $TOP

# Waves: testbench signals only (adding the whole chip recursively is huge and slow).
# Add more as you need them, for example:
#   add wave sim:/emu_top_tb/dut/u_driver/*
#   add wave sim:/emu_top_tb/dut/u_chip/*
#   add wave sim:/$TOP/*
do emu_wave.do

view wave
view structure
view signals

run -all
wave zoom full
