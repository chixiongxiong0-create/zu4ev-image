# Run after impl_1 completes, before any programming.
set repo [file normalize [file join [file dirname [info script]] ../../..]]
set out [file join $repo build ibex_small ae_board_reports]
file mkdir $out
open_run impl_1
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out timing_summary.rpt]
report_utilization -hierarchical -file [file join $out utilization.rpt]
report_drc -file [file join $out drc.rpt]
report_route_status -file [file join $out route_status.rpt]
report_bus_skew -file [file join $out bus_skew.rpt]
report_clocks -file [file join $out clocks.rpt]
set worst_setup [get_timing_paths -delay_type max -max_paths 1]
set worst_hold [get_timing_paths -delay_type min -max_paths 1]
if {![llength $worst_setup] || ![llength $worst_hold]} {error "Missing timing paths"}
set setup_slack [get_property SLACK $worst_setup]
set hold_slack [get_property SLACK $worst_hold]
puts "IBEX_BOARD_TIMING setup_slack=$setup_slack hold_slack=$hold_slack"
if {$setup_slack < 0 || $hold_slack < 0} {error "Board timing failed"}
write_debug_probes -force [file join $out camera_top.ltx]
puts "IBEX_BOARD_TIMING_PASS"
