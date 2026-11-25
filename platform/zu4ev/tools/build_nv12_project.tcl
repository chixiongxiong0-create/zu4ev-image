set nv_repo [file normalize [file join [file dirname [info script]] ../../..]]
set nv_base [file join $nv_repo build h264_vcu_final project camera.xpr]
set nv_out [file join $nv_repo build nv12_platform]
if {[info exists ::env(SC130_NV12_PROJECT_OUT)]} {set nv_out [file normalize $::env(SC130_NV12_PROJECT_OUT)]}
if {[file exists [file join $nv_out project nv12.xpr]]} {error "Destination already exists; choose a new SC130_NV12_PROJECT_OUT"}
file mkdir $nv_out
open_project $nv_base
save_project_as nv12 [file join $nv_out project] -exclude_run_results
set old_rom [lindex [get_files *board_rom.mem] 0]
if {$old_rom eq "" || ![file isfile $old_rom]} {error "Validated Ibex ROM missing"}
set rom_type [get_property FILE_TYPE $old_rom]
file copy $old_rom [file join $nv_out board_rom.mem]
remove_files $old_rom
add_files [file join $nv_out board_rom.mem]
set_property FILE_TYPE $rom_type [get_files *board_rom.mem]
set bd [get_files ps_system.bd]
if {![string match ${nv_out}/* $bd]} {error "BD is not isolated: $bd"}
open_bd_design $bd
source [file join $nv_repo platform zu4ev hardware add_nv12.tcl]
source [file join $nv_repo platform zu4ev tools add_hierarchy_sources.tcl]
source [file join $nv_repo integration small board apply_sources.tcl]
set_property verilog_define [lsort -unique [concat [get_property VERILOG_DEFINE [get_filesets sources_1]] {SC130_NV12}]] [get_filesets sources_1]
set_property verilog_define [lsort -unique [concat [get_property VERILOG_DEFINE [get_filesets sim_1]] {SC130_NV12}]] [get_filesets sim_1]
if {[llength [get_files -quiet *board_rom.mem]] != 1} {error "Validated Ibex ROM missing"}
if {![string match *IBEX_BOARD_ROM_FILE* [get_property VERILOG_DEFINE [get_filesets sources_1]]]} {error "Ibex ROM macro missing"}
set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs synth_1]
generate_target all $bd
foreach old_wrapper [get_files -quiet *ps_system_wrapper.v] {remove_files $old_wrapper}
make_wrapper -files $bd -top -import
update_compile_order -fileset sources_1
check_syntax -fileset sources_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Full synthesis failed"}
open_run synth_1
report_utilization -file [file join $nv_out utilization.rpt]
report_timing_summary -file [file join $nv_out timing.rpt]
report_cdc -file [file join $nv_out cdc.rpt]
puts NV12_FULL_SYNTH_PASS
