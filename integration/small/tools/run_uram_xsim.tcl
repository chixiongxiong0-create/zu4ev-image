set repo [file normalize [file join [file dirname [info script]] ../../..]]
set base [file join $repo integration small]
set mode cpu
if {[info exists ::env(IBEX_URAM_TEST)]} {set mode $::env(IBEX_URAM_TEST)}
if {$mode ni {cpu loader}} {error "IBEX_URAM_TEST must be cpu or loader"}
set work [file join $repo build ibex_small uram_$mode]
create_project -force uram_$mode $work -part xczu4ev-sfvc784-2-i
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]
set_property source_mgmt_mode None [current_project]
set f [open [file join $base sources.txt] r]
foreach rel [split [read $f] "\n"] {if {$rel ne "" && ![string match */prim_xilinx/rtl/prim_clock_gating.sv $rel]} {add_files [file join $repo $rel]}}
close $f
add_files [file join $base board prim_clock_gating_ultrascale.sv]
add_files [glob [file join $base rtl *.sv]]
set_property include_dirs [list [file join $repo vendor lowrisc_ip ip prim rtl] [file join $repo vendor lowrisc_ip dv sv dv_utils]] [current_fileset]
set_property verilog_define {SYNTHESIS FPGA_XILINX} [current_fileset]
set_property top ibex_small_system [current_fileset]
add_files -fileset sim_1 [file join $base sim tb_uram_${mode}.sv]
add_files -fileset sim_1 [file join $base sw selftest.mem]
set_property file_type {Memory Initialization Files} [get_files selftest.mem]
set_property top tb_uram_$mode [get_filesets sim_1]
set_property verilog_define {SYNTHESIS FPGA_XILINX} [get_filesets sim_1]
set_property xsim.simulate.runtime {1600us} [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation
quit
