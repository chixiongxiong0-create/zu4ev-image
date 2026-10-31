# Run on the open ECO-corrected routed design; do not reopen the old run.
set repo [file normalize [file join [file dirname [info script]] ../../..]]
set out [file join $repo build ibex_small board_reports]
file mkdir $out
report_route_status -file [file join $out route_status.rpt]
report_drc -file [file join $out drc.rpt]
if {[llength [get_drc_violations -filter {SEVERITY == Error}]]} {error "DRC errors remain"}
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out timing_summary.rpt]
set setup_slack [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
set hold_slack [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
puts "IBEX_BOARD_TIMING setup_slack=$setup_slack hold_slack=$hold_slack"
if {$setup_slack < 0 || $hold_slack < 0} {error "Board timing failed"}
report_utilization -hierarchical -file [file join $out utilization.rpt]
report_clocks -file [file join $out clocks.rpt]
puts "IBEX_BOARD_UNROUTED=[llength [get_nets -hier -filter {ROUTE_STATUS == UNROUTED || ROUTE_STATUS == PARTIAL}]]"
write_debug_probes -force [file join $out camera_top.ltx]
puts IBEX_BOARD_TIMING_PASS
