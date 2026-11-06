# Source only for ibex_small_core's fixed board configuration. Keep sources.txt
# unchanged for generic configurations. Never deletes repository files.
set ibex_board_repo [file normalize [file join [file dirname [info script]] ../../..]]
set ibex_board_manifest [file join $ibex_board_repo integration small board_sources.txt]
set ibex_board_handle [open $ibex_board_manifest r]
set ibex_board_selected {}
foreach ibex_board_line [split [read $ibex_board_handle] "\n"] {
    set ibex_board_line [string trim $ibex_board_line]
    if {$ibex_board_line eq "" || [string match #* $ibex_board_line]} {continue}
    set ibex_board_path [file normalize [file join $ibex_board_repo $ibex_board_line]]
    if {![file isfile $ibex_board_path]} {error "Missing board RTL: $ibex_board_path"}
    lappend ibex_board_selected $ibex_board_path
}
close $ibex_board_handle
# Restrict pruning to lowRISC primitive module/package sources; preserve header
# includes, unrelated IP, application RTL, constraints, ROMs and run settings.
set ibex_board_removed {}
foreach ibex_board_file [get_files -quiet -of_objects [get_filesets sources_1]] {
    set ibex_board_normal [file normalize $ibex_board_file]
    if {[string match */vendor/lowrisc_ip/ip/prim*/rtl/*.sv $ibex_board_normal] &&
        [lsearch -exact $ibex_board_selected $ibex_board_normal] < 0 &&
        [get_property FILE_TYPE $ibex_board_file] ne "Verilog Header"} {
        lappend ibex_board_removed $ibex_board_file
    }
}
if {[llength $ibex_board_removed]} {remove_files $ibex_board_removed}
foreach ibex_board_file $ibex_board_selected {
    if {![llength [get_files -quiet $ibex_board_file]]} {add_files $ibex_board_file}
}
set ibex_board_includes [get_property INCLUDE_DIRS [get_filesets sources_1]]
foreach ibex_board_dir {vendor/lowrisc_ip/ip/prim/rtl vendor/lowrisc_ip/dv/sv/dv_utils} {
    lappend ibex_board_includes [file join $ibex_board_repo $ibex_board_dir]
}
set_property INCLUDE_DIRS [lsort -unique $ibex_board_includes] [get_filesets sources_1]
update_compile_order -fileset sources_1
puts "IBEX_BOARD_SOURCES selected=[llength $ibex_board_selected] removed=[llength $ibex_board_removed]"
