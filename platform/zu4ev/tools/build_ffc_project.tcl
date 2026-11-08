# Recreate a separate FFC project from the validated NV12 platform.
set ffc_repo [file normalize [file join [file dirname [info script]] ../../..]]
set ffc_base [file join $ffc_repo build nv12_platform project nv12.xpr]
set ffc_out [file join $ffc_repo build ffc_project]
if {[info exists ::env(FFC_PROJECT_OUT)]} {set ffc_out [file normalize $::env(FFC_PROJECT_OUT)]}
if {[file exists [file join $ffc_out project ffc.xpr]]} {error "FFC destination exists"}
file mkdir $ffc_out
open_project $ffc_base
save_project_as ffc [file join $ffc_out project] -exclude_run_results
# The validated NV12 project may refer to a moved ROM. Use the known matching
# 1371-word baseline copy rather than silently building an empty boot store.
set ffc_rom [file join $ffc_repo build h264_vcu_final board_rom.mem]
if {![file isfile $ffc_rom]} {error "Validated Ibex ROM unavailable"}
set f [open $ffc_rom r];set words [llength [split [string trim [read $f]] \n]];close $f
if {$words != 1371} {error "Unexpected Ibex ROM word count"}
remove_files [get_files *board_rom.mem]
file copy -force $ffc_rom [file join $ffc_out board_rom.mem]
add_files [file join $ffc_out board_rom.mem]
set_property FILE_TYPE {Memory Initialization Files} [get_files *board_rom.mem]
source [file join $ffc_repo platform zu4ev tools add_hierarchy_sources.tcl]
source [file join $ffc_repo integration small board apply_sources.tcl]
set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs synth_1]
update_compile_order -fileset sources_1
check_syntax -fileset sources_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "FFC synthesis failed"}
launch_runs impl_1 -to_step route_design -jobs 1
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "FFC implementation failed"}
open_run impl_1
set ::env(H264_REPORT_DIR) [file join $ffc_out route_reports]
source [file join $ffc_repo platform zu4ev tools verify_h264_timing.tcl]
write_bitstream -force [file join $ffc_out camera_top.bit]
puts FFC_BUILD_PASS
