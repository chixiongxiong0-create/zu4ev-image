# Vivado2025.1 VCU1.2 clock_checks reads nonexistent BD CONFIG.HDL_ENCODER_EN.
# Keep vendor checks and repair encoder clock metadata from the connected pin.
# Session-local workaround: never modifies the installed IP repository.
proc zu4ev_fix_vcu_clock_metadata {} {
    set ns ::xilinx.com_ip_vcu_1.2
    if {![llength [info procs ${ns}::clock_checks_original]]} {
        rename ${ns}::clock_checks ${ns}::clock_checks_original
        proc ${ns}::clock_checks {cellPath otherInfo} {
            clock_checks_original $cellPath $otherInfo
            set ip [get_bd_cells $cellPath]
            if {[string equal -nocase [get_property CONFIG.ENABLE_ENCODER $ip] true]} {
                set mhz [expr {[get_property CONFIG.FREQ_HZ [get_bd_pins $ip/m_axi_enc_aclk]] / 1000000.0}]
                if {$mhz < 50 || $mhz > 333} {error "VCU encoder AXI clock outside 50..333 MHz"}
                set_property CONFIG.AXI_ENC_CLK $mhz $ip
                set_property CONFIG.ENC_CLK $mhz $ip
            }
        }
    }
}
zu4ev_fix_vcu_clock_metadata
set_property CONFIG.AXI_ENC_CLK 200 [get_bd_cells vcu]
set_property CONFIG.ENC_CLK 200 [get_bd_cells vcu]
validate_bd_design
save_bd_design
