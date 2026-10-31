# Equivalent post-route replacement: fresh BUFGCE has correct source attribute.
# No DRC is waived. Preserve all pins, inversions, CE mode and physical BEL.
set gate [get_cells -hier -filter {NAME =~ *core_clock_gate* && REF_NAME == BUFGCE}]
if {[llength $gate] != 1} {error "Expected one Ibex clock gate"}
set gate_name [get_property NAME $gate]
set gate_bel [get_bels -of_objects $gate]
set gate_ce [get_property CE_TYPE $gate]
set gate_iinv [get_property IS_I_INVERTED $gate]
set gate_ceinv [get_property IS_CE_INVERTED $gate]
set gate_nets [dict create]
foreach pin {I CE O} {dict set gate_nets $pin [get_nets -of_objects [get_pins $gate_name/$pin]]}
puts "IBEX_ECO_BEFORE cell=$gate_name bel=$gate_bel nets=$gate_nets"
remove_cell $gate
create_cell -reference BUFGCE $gate_name
set gate [get_cells $gate_name]
set_property -dict [list SIM_DEVICE ULTRASCALE_PLUS CE_TYPE $gate_ce IS_I_INVERTED $gate_iinv IS_CE_INVERTED $gate_ceinv] $gate
foreach pin {I CE O} {connect_net -net [dict get $gate_nets $pin] -objects [get_pins $gate_name/$pin]}
place_cell [list $gate_name $gate_bel]
foreach pin {I CE O} {
 if {[get_nets -of_objects [get_pins $gate_name/$pin]] ne [dict get $gate_nets $pin]} {error "ECO connectivity mismatch $pin"}
}
puts "IBEX_ECO_AFTER cell=$gate_name bel=[get_bels -of_objects $gate] SIM_DEVICE=[get_property SIM_DEVICE $gate] CE_TYPE=[get_property CE_TYPE $gate]"
report_drc -checks [get_drc_checks ADEF-911]
