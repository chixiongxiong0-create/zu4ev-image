# Run prepare_ae_copy.py first. This modifies only the isolated build tree.
set repo [file normalize [file join [file dirname [info script]] ../../..]]
set base [file join $repo integration small]
set copy [file join $repo build ibex_small ae_board]
if {[info exists ::env(IBEX_BOARD_COPY)]} {set copy [file normalize $::env(IBEX_BOARD_COPY)]}
set rom [file join $repo build ibex_small ae_live ae_live.mem]
if {[info exists ::env(IBEX_BOARD_ROM)]} {set rom [file normalize $::env(IBEX_BOARD_ROM)]}
if {![file isfile $rom]} {error "Build selected ROM first: $rom"}
# Dense 32-bit images only: validate the entire image before trimming zero tail.
# This derives the boot-ROM depth from the selected firmware, never silently
# truncating a caller-selected depth or leaving uninitialized bootstrap words.
set rom_handle [open $rom r]
set rom_words [list]
set boot_words 0
foreach line [split [read $rom_handle] "\n"] {
  set word [string trim $line]
  if {$word eq ""} {continue}
  if {![regexp {^[0-9a-fA-F]{8}$} $word]} {error "Expected dense 8-digit hexadecimal ROM words: $rom"}
  lappend rom_words $word
  if {[string trimleft $word 0] ne ""} {set boot_words [llength $rom_words]}
}
close $rom_handle
if {[llength $rom_words] > 65536 || [llength $rom_words] == 0} {error "ROM must contain 1..65536 words"}
if {$boot_words == 0} {set boot_words 1}
set rom_handle [open [file join $copy board_rom.mem] w]
puts $rom_handle [join [lrange $rom_words 0 [expr {$boot_words-1}]] "\n"]
close $rom_handle
puts "IBEX_BOOT_IMAGE_WORDS $boot_words (zero padded at runtime to 65536)"
if {![file exists [file join $copy project camera.xpr]]} {
  if {[llength [get_projects -quiet]]} {close_project}
  source -notrace [file join $copy tools create_full_ae_project.tcl]
}
open_project [file join $copy project camera.xpr]
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]
set_property source_mgmt_mode None [current_project]
set f [open [file join $base sources.txt] r]
foreach rel [split [read $f] "\n"] {if {$rel ne "" && ![string match */prim_xilinx/rtl/prim_clock_gating.sv $rel]} {add_files [file join $repo $rel]}}
add_files [file join $base board prim_clock_gating_ultrascale.sv]
close $f
add_files [glob [file join $base rtl *.sv]]
add_files [file join $base board ibex_board_debug.sv]
add_files [file join $copy board_rom.mem]
set_property file_type {Memory Initialization Files} [get_files board_rom.mem]
set_property include_dirs [list [file join $repo vendor lowrisc_ip ip prim rtl] [file join $repo vendor lowrisc_ip dv sv dv_utils]] [get_filesets sources_1]
set_property verilog_define [list SC130_UVC FPGA_XILINX {IBEX_BOARD_ROM_FILE="board_rom.mem"} IBEX_BOARD_BOOT_WORDS=$boot_words] [get_filesets sources_1]
create_ip -name jtag_axi -vendor xilinx.com -library ip -version 1.2 -module_name ibex_jtag_axi
set_property CONFIG.PROTOCOL 2 [get_ips ibex_jtag_axi]
create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name ibex_reset_vio
set_property -dict {CONFIG.C_PROBE_IN0_WIDTH 4 CONFIG.C_PROBE_OUT0_WIDTH 1 CONFIG.C_PROBE_OUT0_INIT_VAL 0} [get_ips ibex_reset_vio]
generate_target all [get_ips {ibex_jtag_axi ibex_reset_vio}]
set_property top camera_top [get_filesets sources_1]
update_compile_order -fileset sources_1
set_property STEPS.OPT_DESIGN.TCL.PRE [file join $base board impl_init.tcl] [get_runs impl_1]
puts "IBEX_AE_COPY_CONFIGURED [get_property PART [current_project]]"
