# Match the upstream Xilinx clock-gate primitive to the actual target family.
# Applied after synthesized netlist loading, without editing upstream RTL.
set ibex_gate [get_cells -hier -filter {NAME =~ *core_clock_gate* && REF_NAME == BUFGCE}]
if {[llength $ibex_gate] != 1} {error "Expected one Ibex BUFGCE"}
set_property SIM_DEVICE ULTRASCALE_PLUS $ibex_gate
puts "IBEX_BUFGCE_SIM_DEVICE=[get_property SIM_DEVICE $ibex_gate]"
source [file join [file dirname [info script]] isp_snapshot_cdc.tcl]
source [file join [file dirname [info script]] isp_config_cdc.tcl]
