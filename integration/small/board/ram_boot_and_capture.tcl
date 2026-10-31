# Temporary DDR boot only. Never erases/programs QSPI.
# xsdb ram_boot_ltm.tcl RAM_FSBL PMUFW BOOT_BIN FIT_IMAGE READY_SYMBOL
if {$argc!=9} {error "usage: ram_boot_ltm.tcl RAM_FSBL PMUFW BOOT_BIN FIT_IMAGE READY_SYMBOL OUTPUT_DIR LOG_ADDR RECORDS_ADDR CORE_ADDR"}
lassign $argv fsbl pmufw boot fit ready out log_addr records_addr core_addr
foreach path [list $fsbl $pmufw $boot $fit] {if {![file isfile $path]} {error "Missing $path"}}
if {[file size $boot]>0xc00000 || [file size $fit]>0x1400000} {error IMAGE_TOO_LARGE}
proc upload {path base} {
 targets -set -filter {name == "PSU"}
 set input [open $path rb]
 set part "$path.stage"
 set offset 0
 while {![eof $input]} {
  set data [read $input 65536]
  if {![string length $data]} {break}
  set output [open $part wb]
  puts -nonewline $output $data
  close $output
  dow -data $part [expr {$base+$offset}]
  incr offset [string length $data]
  if {$offset%0x100000==0} {puts "RAM_STAGE bytes=$offset source=$path"}
 }
 close $input
 file delete $part
 puts "RAM_UPLOAD_COMPLETE bytes=$offset source=$path"
}
connect -url tcp:127.0.0.1:3121
targets -set -filter {name == "PSU"}
mwr 0xff5e0200 0x100
targets -set -filter {name == "Cortex-A53 #0"}
rst -system
after 1000
targets -set -filter {name == "PSU"}
mwr 0xff5e0200 0x2100
mwr 0xffd80118 0x00100000
mwr 0xffd80120 0x00100000
set powered 0
for {set i 0} {$i<100} {incr i} {
 if {([mrd -value 0xffd80100]&0x00100000)!=0} {set powered 1;break}
 after 10
}
if {!$powered} {error USB_PREPOWER_TIMEOUT}
mwr 0xffca0038 0x1ff
after 500
targets -set -filter {name =~ "MicroBlaze PMU"}
dow $pmufw
con
after 500
targets -set -filter {name == "Cortex-A53 #0"}
rst -processor -clear-registers
dow $fsbl
bpremove -all
set breakpoint [bpadd -addr $ready]
con
after 8000
if {[catch {stop} result] && ![string match {*Already stopped*} $result]} {error $result}
set pc [rrd pc]
puts "RAM_READY_PC $pc"
if {![string match -nocase "*[string range $ready 2 end]*" $pc]} {error RAM_READY_NOT_REACHED}
upload $boot 0x30000000
upload $fit 0x10000000
targets -set -filter {name == "Cortex-A53 #0"}
bpremove $breakpoint
con
puts "LTM_RAM_BOOT_DISPATCHED QSPI_UNCHANGED"
# Capture startup records before the 512-slot ring wraps. R5 is never halted.
file mkdir $out
targets -set -filter {name == "Cortex-R5 #0"}
set alive 0
for {set attempt 0} {$attempt<200} {incr attempt} {
 if {![catch {set magic [mrd -value $log_addr]}] && $magic==0x41453552} {
  set count [mrd -value [expr {$log_addr+8}]]
  if {$count<400} {set alive 1;break}
 }
 after 100
}
if {!$alive} {error R5_STARTUP_LOG_NOT_OBSERVED}
after 800
mrd -bin -file [file join $out ae_log_before.bin] $log_addr 8
mrd -force -bin -file [file join $out ae_records.bin] $records_addr [expr {512*17}]
mrd -force -bin -file [file join $out core.bin] $core_addr 4
mrd -bin -file [file join $out ae_log_after.bin] $log_addr 8
puts "R5_STARTUP_CAPTURE_COMPLETE output=$out"
disconnect
exit
