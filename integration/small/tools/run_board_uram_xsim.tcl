set repo [file normalize [file join [file dirname [info script]] ../../..]]
set platform [file normalize [file join $repo ../../ZU4EV/zynq-zu4ev_platform]]
if {[info exists ::env(IBEX_PLATFORM)]} {set platform $::env(IBEX_PLATFORM)}
set base $repo/integration/small
file mkdir $repo/build/uram_verify
set image $repo/build/ibex_small/board_validation/board_validation.mem
if {![file exists $image]} {error "Build board-validation firmware first: $image"}
set f [open $image r]; set lines [split [string trim [read $f]] "\n"]; close $f
set n 0; foreach line $lines {set word [string trim $line]; if {![regexp {^[0-9a-fA-F]{8}$} $word]} {error "Invalid firmware word"}; incr n; if {$word ne "00000000"} {set used $n}}
if {![info exists used]} {set used 1}; if {$n > 65536} {error "Firmware too large"}
set f [open $repo/build/uram_verify/board_validation_uram.mem w]; puts $f [join [lrange $lines 0 [expr {$used-1}]] "\n"]; close $f
set f [open $base/sim/tb_board_validation.sv r]; set tb [read $f]; close $f
set tb [string map [list {.RomFile("board_validation.mem"),} ".RomFile(\"board_validation_uram.mem\"),.ProgramPrimitive(\"ultra\"),.BootImageWords($used),"] $tb]
set f [open $repo/build/uram_verify/tb_board_uram.sv w]; puts -nonewline $f $tb; close $f

create_project -force board_validation $repo/build/uram_verify/board_xsim -part xczu4ev-sfvc784-2-i
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]
set_property source_mgmt_mode None [current_project]
set f [open $base/sources.txt r]
foreach rel [split [read $f] "\n"] {if {$rel ne "" && ![string match */prim_xilinx/rtl/prim_clock_gating.sv $rel]} {add_files $repo/$rel}}
close $f
add_files $base/board/prim_clock_gating_ultrascale.sv
add_files [glob $base/rtl/*.sv]
add_files $platform/isp/ltm/isp_axi_regs.sv
add_files $platform/isp/ae/ae_stats_raw10.sv
add_files $platform/rtl/sensor/ae_fe_event.sv
set_property include_dirs [list $repo/vendor/lowrisc_ip/ip/prim/rtl $repo/vendor/lowrisc_ip/dv/sv/dv_utils] [current_fileset]
set_property verilog_define {SYNTHESIS FPGA_XILINX} [current_fileset]
add_files -fileset sim_1 $repo/build/uram_verify/tb_board_uram.sv
add_files -fileset sim_1 $repo/build/uram_verify/board_validation_uram.mem
set_property file_type {Memory Initialization Files} [get_files board_validation_uram.mem]
set_property top tb_board_validation [get_filesets sim_1]
set_property verilog_define {SYNTHESIS FPGA_XILINX} [get_filesets sim_1]
set_property xsim.simulate.runtime {5000us} [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation


quit
