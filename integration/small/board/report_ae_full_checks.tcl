# Run only after the complete project's implementation has routed.
# No bitstream generation or hardware programming is performed here.
if {![info exists ::env(IBEX_BOARD_REPORTS)]} {
  error "Set IBEX_BOARD_REPORTS to the final report directory"
}
set out [file normalize $::env(IBEX_BOARD_REPORTS)]
file mkdir $out
set report_current [expr {[info exists ::env(IBEX_BOARD_REPORT_CURRENT_DESIGN)] && $::env(IBEX_BOARD_REPORT_CURRENT_DESIGN) eq "1"}]
if {!$report_current} {open_run impl_1}
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out timing_summary.rpt]
report_timing -delay_type max -max_paths 10 -path_type full_clock_expanded -file [file join $out setup_paths.rpt]
report_timing -delay_type min -max_paths 10 -path_type full_clock_expanded -file [file join $out hold_paths.rpt]
report_utilization -file [file join $out utilization.rpt]
report_utilization -hierarchical -file [file join $out utilization_hierarchical.rpt]
report_drc -file [file join $out drc.rpt]
report_cdc -details -file [file join $out cdc.rpt]
report_methodology -file [file join $out methodology.rpt]
report_route_status -file [file join $out route_status.rpt]
report_bus_skew -file [file join $out bus_skew.rpt]
report_clocks -file [file join $out clocks.rpt]
report_clock_interaction -file [file join $out clock_interaction.rpt]
report_exceptions -file [file join $out exceptions.rpt]
report_exceptions -coverage -file [file join $out exception_coverage.rpt]
report_exceptions -ignored -file [file join $out ignored_exceptions.rpt]
write_xdc -force -exclude_physical [file join $out effective_timing.xdc]
foreach kind {GRAY_SOURCE PAYLOAD CFG_REQUEST CFG_RESPONSE} {
  set sources [get_cells -hier -filter "IBEX_CDC == $kind"]
  if {![llength $sources]} {error "Missing routed CDC sources: $kind"}
  set outputs [get_pins -of_objects $sources -filter {REF_PIN_NAME == Q}]
  set endpoints [all_fanout -flat -endpoints_only -from $outputs]
  if {![llength $endpoints]} {error "Missing routed CDC destinations: $kind"}
  report_timing -from $sources -to $endpoints -delay_type max -max_paths 5 -path_type full_clock_expanded -file [file join $out cdc_${kind}_paths.rpt]
}
set audit [open [file join $out linked_design_audit.tcldict] w]
set runs {checkpoint_recovery}
if {!$report_current} {
  set runs {}
  foreach r [get_runs] {
    lappend runs [dict create name $r status [get_property STATUS $r] progress [get_property PROGRESS $r]]
  }
}
set blackboxes [get_cells -hier -filter {IS_BLACKBOX == 1}]
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
puts $audit [dict create part [get_property PART [current_design]] top [get_property NAME [current_design]] blackboxes $blackboxes runs $runs setup_slack [get_property SLACK $setup] hold_slack [get_property SLACK $hold]]
close $audit
if {[llength $blackboxes]} {error "Linked design still contains black boxes: $blackboxes"}
puts "IBEX_FULL_REPORTS_COMPLETE $out"
