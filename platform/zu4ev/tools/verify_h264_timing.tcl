# Run in the opened routed design before accepting a deployment artifact.
if {![info exists ::env(H264_REPORT_DIR)]} {error "Set H264_REPORT_DIR"}
set h264_reports [file normalize $::env(H264_REPORT_DIR)]
file mkdir $h264_reports
set h264_timing [report_timing_summary -return_string -max_paths 1]
set h264_file [open [file join $h264_reports timing_acceptance.rpt] w]
puts $h264_file $h264_timing
close $h264_file
if {![string match {*All user specified timing constraints are met.*} $h264_timing]} {
    error "H264 timing acceptance failed: inspect timing_acceptance.rpt"
}
report_drc -file [file join $h264_reports drc_acceptance.rpt]
set h264_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
if {[llength $h264_errors]} {error "H264 DRC errors: $h264_errors"}
set h264_skew [report_bus_skew -return_string]
set h264_file [open [file join $h264_reports bus_skew_acceptance.rpt] w]
puts $h264_file $h264_skew
close $h264_file
if {[string match {*VIOLATED*} $h264_skew]} {error "H264 bus skew constraints violated"}
puts H264_ROUTED_TIMING_DRC_BUS_SKEW_PASS
