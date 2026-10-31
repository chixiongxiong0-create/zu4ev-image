"""Generate an auditable JTAG mailbox comparison using the native reference vectors."""
from pathlib import Path
import json
b=Path(__file__).resolve().parents[1];repo=b.parents[1]
rows=json.loads((repo/'build/ibex_small/ae/vectors.json').read_text())
p=repo/'build/ibex_small/ae/compare_board.tcl'
prefix="""set ax [get_hw_axis]
if {[llength $ax]!=1} {error "Expected exactly one JTAG AXI"}
set ax [lindex $ax 0]
reset_hw_axi $ax
foreach t [get_hw_axi_txns -quiet {ae_read ae_write}] {delete_hw_axi_txn $t}
create_hw_axi_txn ae_read $ax -type READ -address 0023f800 -len 1
create_hw_axi_txn ae_write $ax -type WRITE -address 0023f000 -len 1 -data 00000000
proc ae_read {addr} {
 set t [get_hw_axi_txns ae_read]
 set_property CMD.ADDR [format %08x $addr] $t
 run_hw_axi $t
 set h [get_property DATA $t]
 if {[scan $h %x v]!=1} {error "Invalid AXI data $h"}
 return [expr {$v&0xffffffff}]
}
proc ae_write {addr val} {
 set t [get_hw_axi_txns ae_write]
 set_property CMD.ADDR [format %08x $addr] $t
 set_property DATA [format %08x $val] $t
 run_hw_axi $t
}
if {[ae_read 0x0023f83c]!=0x41454942} {error "AE firmware not ready"}
set version_base [expr {([clock milliseconds]&0x3fffff)<<9}]
set count 0
set max_cycles 0
"""
lines=[prefix,'set cases {']
for r in rows:lines.append(' {'+' '.join(map(str,r['input']+r['expected']))+'}')
lines+=['}',"""foreach row $cases {
 incr count
 set v [expr {($version_base+2*$count)&0xfffffffe}]
 ae_write 0x0023f000 [expr {$v|1}]
 for {set j 1} {$j<=13} {incr j} {ae_write [expr {0x0023f000+4*$j}] [lindex $row [expr {$j-1}]]}
 ae_write 0x0023f000 $v
 set ready 0
 for {set poll 0} {$poll<1000} {incr poll} {
  if {[ae_read 0x0023f800]==$v} {set ready 1;break}
 }
 if {!$ready} {error "AE response timeout case=$count"}
 if {[ae_read 0x0023f804]!=[lindex $row 0]} {error "AE case ID mismatch"}
 set actual {}
 for {set j 0} {$j<10} {incr j} {
  set a [ae_read [expr {0x0023f808+4*$j}]]
  lappend actual $a
  if {$a!=[lindex $row [expr {13+$j}]]} {error "AE mismatch case=$count field=$j actual=$a expected=[lindex $row [expr {13+$j}]]"}
 }
 set cycles [ae_read 0x0023f830]
 if {$cycles>$max_cycles} {set max_cycles $cycles}
 if {[ae_read 0x0023f800]!=$v} {error "AE torn output snapshot"}
 puts "IBEX_AE_BOARD_CASE id=[lindex $row 0] result=$actual cycles=$cycles"
 if {$count%25==0} {puts "IBEX_AE_BOARD_PROGRESS $count"}
}
""",f'puts "IBEX_AE_BOARD_PASS cases={len(rows)} live_r5={sum(x["label"]=="live_r5" for x in rows)} max_cycles=$max_cycles"']
p.write_text('\n'.join(lines)+'\n');print(p)
