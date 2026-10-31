# Held request/response mailboxes have a two-stage toggle before capture.
# Bound each bundled payload to one receiving period; fail if markers vanish.
foreach kind {CFG_REQUEST CFG_RESPONSE} {
 set sources [get_cells -hier -filter "IBEX_CDC == $kind"]
 if {![llength $sources]} {error "Ibex config CDC markers missing: $kind"}
 set source_pins [get_pins -of_objects $sources -filter {REF_PIN_NAME == Q}]
 set sinks [all_fanout -flat -endpoints_only -from $source_pins]
 set clocks [get_clocks -of_objects [get_pins -of_objects [get_cells -of_objects $sinks] -filter {REF_PIN_NAME == C}]]
 if {![llength $sinks] || ![llength $clocks]} {error "Ibex config CDC endpoints missing: $kind"}
 set period 1000000.0
 foreach c $clocks {set period [expr {min($period,[get_property PERIOD $c])}]}
 # Use sequential cells, preserving their launch clock arcs (UG903).
 set_max_delay -datapath_only $period -from $sources -to $sinks
 set_bus_skew $period -from $sources -to $sinks
 puts "IBEX_CONFIG_CDC $kind period=$period"
 puts "IBEX_CONFIG_CDC_COVERAGE $kind sources=[llength $sources] destinations=[llength $sinks]"
}
