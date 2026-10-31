# Hardware readback only. Run after explicitly programming the generated bitstream.
set axis [get_hw_axis]
if {[llength $axis] != 1} {error "Expected exactly one JTAG AXI master"}
set ax [lindex $axis 0]
reset_hw_axi $ax
foreach {label address expected} {
  signature 00200010 600d600d
  first_word 00200000 abcd5578
  last_word 0023fffc deadbeef
} {
  create_hw_axi_txn ibex_$label $ax -type READ -address $address -len 1
  run_hw_axi [get_hw_axi_txns ibex_$label]
  set actual [string tolower [get_property DATA [get_hw_axi_txns ibex_$label]]]
  puts "IBEX_BOARD_READ $label address=$address actual=$actual expected=$expected"
  if {$actual ne $expected} {error "IBEX_BOARD_FAIL $label"}
}
puts IBEX_BOARD_PASS
