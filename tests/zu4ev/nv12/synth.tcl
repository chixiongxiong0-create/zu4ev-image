# Run from repository root: vivado -mode batch -source tests/zu4ev/nv12/synth.tcl
set nv12_root [file normalize [file join [file dirname [info script]] ../../..]]
set nv12_out [file join $nv12_root build nv12_burst_synth]
file mkdir $nv12_out
read_verilog [glob [file join $nv12_root platform zu4ev isp nv12 *.v]]
synth_design -top nv12_isp_ddr_sink -part xczu4ev-sfvc784-2-i -mode out_of_context
create_clock -period 5.000 [get_ports clk]
report_utilization -file [file join $nv12_out utilization.rpt]
report_timing_summary -delay_type max -file [file join $nv12_out timing.rpt]
puts NV12_BURST_SYNTH_DONE
