set repo [file normalize [file join [file dirname [info script]] ../../..]]
file mkdir $repo/build/uram_verify
set image $repo/build/ibex_small/board_validation/board_validation.mem
if {![file exists $image]} {error "Build board-validation firmware first: $image"}
set f [open $image r]; set lines [split [string trim [read $f]] "\n"]; close $f
set n 0; foreach line $lines {set word [string trim $line]; if {![regexp {^[0-9a-fA-F]{8}$} $word]} {error "Invalid firmware word"}; incr n; if {$word ne "00000000"} {set used $n}}
if {![info exists used]} {set used 1}; if {$n > 65536} {error "Firmware too large"}
set f [open $repo/build/uram_verify/board_validation_uram.mem w]; puts $f [join [lrange $lines 0 [expr {$used-1}]] "\n"]; close $f
create_project -force uram_mem $repo/build/uram_verify/synth -part xczu4ev-sfvc784-2-i
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]
read_verilog -sv $repo/integration/small/rtl/ibex_small_mem.sv
add_files $repo/build/uram_verify/board_validation_uram.mem
set_property file_type {Memory Initialization Files} [get_files board_validation_uram.mem]
synth_design -top ibex_small_mem -part xczu4ev-sfvc784-2-i -mode out_of_context -generic [list ProgramPrimitive=ultra RamPrimitive=ultra BootImageWords=$used RomFile=board_validation_uram.mem]
set program [get_cells -hier -filter {REF_NAME =~ URAM* && NAME =~ *gen_program_ultra*}]
set ram [get_cells -hier -filter {REF_NAME =~ URAM* && NAME =~ *u_ram*}]
puts "PROGRAM_URAM_COUNT [llength $program]"
puts "DATA_URAM_COUNT [llength $ram]"
report_utilization -file $repo/build/uram_verify/synth_utilization.rpt
if {[llength $program] == 0} {error "Program store has no URAM primitives"}
quit
