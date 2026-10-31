# Diagnostic only: never launch runs or program hardware. Run in a separate
# Vivado batch process with -tclargs checkpoint|project [unique-output-dir].
set root [file normalize [file join [file dirname [info script]] ../../..]]
set copy [file join $root build ibex_small ae_board_uram_validation_20261029]
set original [file join $copy reports final_uram]
set mode [lindex $argv 0]
if {$mode ni {checkpoint project}} {error "Expected checkpoint or project"}
set trace_out [lindex $argv 1]
if {$trace_out eq ""} {set trace_out [file join $original critical_trace_${mode}_[clock seconds]]}
set trace_out [file normalize $trace_out]
if {[file exists $trace_out]} {error "Refusing existing trace output: $trace_out"}
file mkdir $trace_out
set_param general.maxThreads 1
create_msg_db [file join $trace_out messages.pb]
set trace_fd [open [file join $trace_out command_counts.tsv] w]
puts $trace_fd "phase\tcommand\tcritical_count\tresult_code"
flush $trace_fd
set trace_serial 0
proc critical_count {} {return [get_msg_config -count -severity {CRITICAL WARNING}]}
proc trace_message_dump {} {
  global trace_out trace_serial
  write_messages -force -severity {{CRITICAL WARNING}} -suppression ALL [file join $trace_out [format "critical_%04d.txt" $trace_serial]]
}
proc trace_command {name args} {
  global trace_fd trace_serial
  incr trace_serial
  set before [critical_count]
  puts $trace_fd "before\t$name\t$before\t-"
  flush $trace_fd
  set code [catch {uplevel 1 [list ::trace_original_$name {*}$args]} result opts]
  set after [critical_count]
  puts $trace_fd "after\t$name\t$after\t$code"
  flush $trace_fd
  puts "CRITICAL_TRACE $name before=$before after=$after code=$code"
  if {$after > $before} {trace_message_dump}
  return -options $opts $result
}
foreach command {open_checkpoint open_project open_run close_design report_timing_summary report_timing report_utilization report_drc report_cdc report_methodology report_route_status report_bus_skew report_clocks report_clock_interaction report_exceptions write_xdc get_cells get_pins all_fanout get_timing_paths write_checkpoint write_debug_probes write_bitstream} {
  rename ::$command ::trace_original_$command
  proc ::$command {args} [format {return [uplevel 1 [list trace_command %s {*}$args]]} $command]
}
set code [catch {
  if {$mode eq "checkpoint"} {
    open_checkpoint [file join $original camera_top_routed.dcp]
    set ::env(IBEX_BOARD_REPORT_CURRENT_DESIGN) 1
  } else {
    open_project [file join $copy project camera.xpr]
    set ::env(IBEX_BOARD_REPORT_CURRENT_DESIGN) 0
  }
  set ::env(IBEX_BOARD_REPORTS) $trace_out
  source [file join $root integration small board report_ae_full_checks.tcl]
  write_checkpoint [file join $trace_out camera_top_routed.dcp]
  write_debug_probes [file join $trace_out camera_top.ltx]
  set setup [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
  set hold [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]
  if {$setup < 0 || $hold < 0} {error "Timing failed setup=$setup hold=$hold"}
  write_bitstream [file join $trace_out camera_top.bit]
} result opts]
trace_message_dump
puts $trace_fd "final\t$mode\t[critical_count]\t$code"
close $trace_fd
if {$code} {puts stderr [dict get $opts -errorinfo]}
close_msg_db -file [file join $trace_out messages.pb]
exit $code
