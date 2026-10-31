# Apply after synthesis. Registers are selected by RTL attributes, independent
# of camera/ISP instance paths. Fail closed if synthesis removed the markers.
set gray_sources [get_cells -hier -filter {IBEX_CDC == GRAY_SOURCE}]
set gray_first [get_cells -hier -filter {IBEX_CDC == GRAY_FIRST}]
set snapshot_sources [get_cells -hier -filter {IBEX_CDC == PAYLOAD}]
foreach group [list $gray_sources $gray_first $snapshot_sources] {
 if {[llength $group] == 0} {error "Ibex snapshot CDC register markers missing"}
}
set gray_d [get_pins -of_objects $gray_first -filter {REF_PIN_NAME == D}]
set video_clocks [get_clocks -of_objects [get_pins -of_objects $gray_sources -filter {REF_PIN_NAME == C}]]
set cpu_clocks [get_clocks -of_objects [get_pins -of_objects $gray_first -filter {REF_PIN_NAME == C}]]
if {![llength $video_clocks] || ![llength $cpu_clocks]} {error "Ibex CDC clock resolution failed"}
set video_period 1000000.0
set cpu_period 1000000.0
foreach c $video_clocks {set video_period [expr {min($video_period,[get_property PERIOD $c])}]}
foreach c $cpu_clocks {set cpu_period [expr {min($cpu_period,[get_property PERIOD $c])}]}
# Half the faster period bounds both arrival spread and datapath latency.
set gray_budget [expr {0.5*min($video_period,$cpu_period)}]
# Sequential cells retain the launch clock arc; Q pins would segment paths.
set_max_delay -datapath_only $gray_budget -from $gray_sources -to $gray_d
set_bus_skew $gray_budget -from $gray_sources -to $gray_d
set payload_q [get_pins -of_objects $snapshot_sources -filter {REF_PIN_NAME == Q}]
set payload_sinks [all_fanout -flat -endpoints_only -from $payload_q]
if {![llength $payload_sinks]} {error "Ibex snapshot payload endpoints missing"}
# Acknowledgement traverses two synchronizer stages before consumption. One
# receiving period is conservative and leaves a full receiving cycle margin.
set_max_delay -datapath_only $cpu_period -from $snapshot_sources -to $payload_sinks
puts "IBEX_ISP_CDC video_period=$video_period cpu_period=$cpu_period gray_budget=$gray_budget"
puts "IBEX_ISP_CDC_COVERAGE gray_sources=[llength $gray_sources] gray_destinations=[llength $gray_d] payload_sources=[llength $snapshot_sources] payload_destinations=[llength $payload_sinks]"
