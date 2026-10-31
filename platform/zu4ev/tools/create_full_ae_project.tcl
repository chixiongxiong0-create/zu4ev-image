# Generation only. Source this copy from a package_full_ae_project.py bundle.
set full_ae_root [file normalize [file join [file dirname [info script]] ..]]
if {![file isfile [file join $full_ae_root source_manifest.json]]} {
    error "Prepare an isolated source bundle with package_full_ae_project.py first"
}
set full_ae_project_dir [file join $full_ae_root project]
if {[file exists $full_ae_project_dir]} {error "Project destination already exists: $full_ae_project_dir"}
if {[llength [get_projects -quiet]]} {error "Use a fresh Vivado session"}

proc full_ae_relative {base target} {
    set a [file split [file normalize $base]]
    set b [file split [file normalize $target]]
    while {[llength $a] && [llength $b] && [string equal -nocase [lindex $a 0] [lindex $b 0]]} {
        set a [lrange $a 1 end]; set b [lrange $b 1 end]
    }
    set result {}
    foreach ignored $a {lappend result ..}
    return [file join {*}[concat $result $b]]
}
proc full_ae_inside {root path} {
    set relative [full_ae_relative $root $path]
    return [expr {[file pathtype $relative] eq "relative" && [lindex [file split $relative] 0] ne ".."}]
}
proc full_ae_runs_idle {} {
    set rows {}
    foreach run [get_runs -quiet] {
        set status [get_property STATUS $run]
        set progress [get_property PROGRESS $run]
        lappend rows [dict create name [get_property NAME $run] status $status progress $progress]
        if {![string equal -nocase $status "Not started"] || $progress ni {0 0% 0.0%}} {
            error "Generation-only run audit failed: $run status=$status progress=$progress"
        }
    }
    return $rows
}

create_project camera $full_ae_project_dir -part xczu4ev-sfvc784-2-i
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property verilog_define {SC130_UVC} [get_filesets sources_1]
source -notrace [file join $full_ae_root tools add_hierarchy_sources.tcl]
add_files -fileset constrs_1 [list [file join $full_ae_root constraints board.xdc] [file join $full_ae_root constraints pl_ddr4.xdc]]
foreach name {camera_clocks camera_ila csi2_rx_uvc uvc_ila pl_ddr4} {
    source -notrace [file join $full_ae_root hardware ${name}.tcl]
}
source -notrace [file join $full_ae_root isp ltm add_to_project.tcl]
source -notrace [file join $full_ae_root isp tnr create_ip.tcl]

# Preserve initialization contents while expressing COE references relative to
# each XCI, so relocation does not depend on the original bundle location.
foreach name {ltm_tone_rom ltm_tone_bank} {
    set ip [get_ips $name]
    set ip_dir [file dirname [get_property IP_FILE $ip]]
    set_property CONFIG.Coe_File [full_ae_relative $ip_dir [file join $full_ae_root isp ltm base_tone.coe]] $ip
}
generate_target all [get_ips -quiet]
source -notrace [file join $full_ae_root hardware ps_system.tcl]
set full_ae_bd [get_files ps_system.bd]
validate_bd_design
save_bd_design
generate_target all $full_ae_bd
make_wrapper -files $full_ae_bd -top -import
set_property top camera_top [get_filesets sources_1]
set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs synth_1]
update_compile_order -fileset sources_1
check_syntax -fileset sources_1

set full_ae_files {}
foreach f [get_files -all -quiet] {
    set path [file normalize $f]
    if {![file exists $path]} {error "Missing project source: $path"}
    if {[full_ae_inside $full_ae_root $path]} {
        lappend full_ae_files [dict create path [full_ae_relative $full_ae_root $path] scope bundle]
    } elseif {[info exists ::env(XILINX_VIVADO)] && [full_ae_inside $::env(XILINX_VIVADO) $path]} {
        lappend full_ae_files [dict create path $path scope vivado_library]
    } else {error "External source dependency: $path"}
}
set full_ae_ips {}
foreach ip [get_ips -quiet] {
    lappend full_ae_ips [dict create name [get_property NAME $ip] ipdef [get_property IPDEF $ip] file [full_ae_relative $full_ae_root [get_property IP_FILE $ip]]]
}
set full_ae_runs [full_ae_runs_idle]
set full_ae_manifest [dict create scope generation_only vivado [version -short] part [get_property PART [current_project]] top [get_property TOP [get_filesets sources_1]] defines [get_property VERILOG_DEFINE [get_filesets sources_1]] files $full_ae_files ips $full_ae_ips runs $full_ae_runs]
file mkdir [file join $full_ae_root reports]
set full_ae_handle [open [file join $full_ae_root reports generation_manifest.tcldict] w]
puts $full_ae_handle $full_ae_manifest
close $full_ae_handle
close_project
puts "FULL_AE_GENERATION_ONLY_COMPLETE: [file join $full_ae_project_dir camera.xpr]"
