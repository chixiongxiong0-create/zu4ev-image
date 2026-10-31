# Add the complete live-capture LTM path to an already-open project.
set ltm_dir [file dirname [file normalize [info script]]]
set ltm_repo [file normalize [file join $ltm_dir ../..]]
set ltm_existing {}
foreach ltm_ip [get_ips -quiet] {
    lappend ltm_existing [get_property NAME $ltm_ip]
}
foreach {ltm_name ltm_script} {
 ltm_line_bram create_ip.tcl
 ltm_tone_rom create_tone_ip.tcl
 ltm_tone_bank create_tone_bank_ip.tcl
 ltm_ingress_bram create_ingress_ip.tcl
} {
 if {[lsearch -exact $ltm_existing $ltm_name]<0} {source -notrace [file join $ltm_dir $ltm_script]}
}
set ltm_sources [concat [glob [file join $ltm_dir *.sv]] [list [file join $ltm_repo isp isp_capture_frontend.sv] [file join $ltm_repo isp ae ae_stats_raw10.sv]]]
set ltm_existing_sources [get_files -of_objects [get_filesets sources_1]]
foreach ltm_source $ltm_sources {
 if {[lsearch -exact $ltm_existing_sources $ltm_source]<0} {add_files $ltm_source}
}
set_property include_dirs [lsort -unique [concat [get_property include_dirs [get_filesets sources_1]] [list $ltm_dir]]] [get_filesets sources_1]
