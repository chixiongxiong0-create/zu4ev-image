set repo [file normalize [file join [file dirname [info script]] ../../..]]
set base [file join $repo integration small]
set work [file join $repo build ibex_small xsim_ae]
file mkdir $work
create_project -force ibex_small $work -part xczu4ev-sfvc784-2-i
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]
set_property source_mgmt_mode None [current_project]
set f [open [file join $base sources.txt] r]
foreach rel [split [read $f] "\n"] { if {$rel ne "" && ![string match */prim_xilinx/rtl/prim_clock_gating.sv $rel]} { add_files [file join $repo $rel] } }
close $f
add_files [file join $base board prim_clock_gating_ultrascale.sv]
add_files [glob [file join $base rtl *.sv]]
set_property include_dirs [list [file join $repo vendor lowrisc_ip ip prim rtl] [file join $repo vendor lowrisc_ip dv sv dv_utils]] [current_fileset]
set_property verilog_define {SYNTHESIS FPGA_XILINX} [current_fileset]
set_property top ibex_small_system [current_fileset]
add_files -fileset sim_1 [glob [file join $base sim *.sv]]
add_files -fileset sim_1 [file join $base sw selftest.mem]
set_property file_type {Memory Initialization Files} [get_files selftest.mem]
set_property top tb_ibex_ae [get_filesets sim_1]
set_property verilog_define {SYNTHESIS FPGA_XILINX} [get_filesets sim_1]
set_property xsim.simulate.runtime {100ms} [get_filesets sim_1]
set_property xsim.elaborate.debug_level typical [get_filesets sim_1]
add_files -fileset sim_1 [list [file join $base ae ae.mem] [file join $base ae vectors.mem]]
set_property file_type {Memory Initialization Files} [get_files {ae.mem vectors.mem}]
set_property include_dirs [list [file join $base ae]] [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation
