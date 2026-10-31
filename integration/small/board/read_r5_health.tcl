# Read-only live status; addresses are from the unchanged matching R5 ELF.
if {$argc!=1} {error "usage: read_r5_health.tcl OUTPUT_DIR"}
set out [lindex $argv 0]
connect -url tcp:127.0.0.1:3121
puts "TARGETS=[targets]"
targets -set -filter {name == "PSU"}
foreach {name addr} {capabilities 0xa0040008 ae_enable 0xa0040248 stats_valid 0xa0040210 stats_seq 0xa0040214 stats_frame 0xa0040218 stats_mean 0xa004021c} {
 puts "R5_HEALTH $name=[mrd -force -value $addr]"
}
targets -set -filter {name == "Cortex-R5 #0"}
mrd -bin -file [file join $out ae_log_before.bin] 0x76bc 8
mrd -force -bin -file [file join $out core.bin] 0x28874 4
after 1000
mrd -bin -file [file join $out ae_log_after.bin] 0x76bc 8
puts R5_HEALTH_CAPTURE_COMPLETE
disconnect
exit
