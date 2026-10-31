# Canonical recursive RTL list for both new and copied projects. No IP settings.
proc camera_rtl_sources {directory} {
    set result [glob -nocomplain -directory $directory *.v *.sv]
    foreach child [glob -nocomplain -types d -directory $directory *] {
        # Historical vendor references duplicate canonical module definitions.
        if {[file tail $child] eq "vendor"} {continue}
        set result [concat $result [camera_rtl_sources $child]]
    }
    return $result
}
set camera_source_root [file normalize [file join [file dirname [info script]] ..]]
set camera_sources [concat [camera_rtl_sources [file join $camera_source_root rtl]] [camera_rtl_sources [file join $camera_source_root isp]]]
foreach camera_source $camera_sources {
    # Copied projects may still point at an older checkout/imported file.
    foreach camera_old [get_files -quiet -of_objects [get_filesets sources_1]] {
        if {[file tail $camera_old] eq [file tail $camera_source] && [file normalize $camera_old] ne [file normalize $camera_source]} {
            remove_files $camera_old
        }
    }
    if {![llength [get_files -quiet $camera_source]]} {add_files $camera_source}
}
set_property top camera_top [get_filesets sources_1]
