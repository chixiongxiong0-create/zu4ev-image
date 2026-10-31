# Actual dual-read BMG ROM. Add to the same project as create_ip.tcl.
# PG058 dual-port ROM; disable optional output registers for one-cycle reads.
set tone_dir [file dirname [file normalize [info script]]]
create_ip -name blk_mem_gen -vendor xilinx.com -library ip -module_name ltm_tone_bank
set tone_desired [dict create \
    CONFIG.Memory_Type True_Dual_Port_RAM \
    CONFIG.Write_Width_A 10 CONFIG.Write_Depth_A 1024 \
    CONFIG.Read_Width_A 10 CONFIG.Read_Width_B 10 CONFIG.Write_Width_B 10 \
    CONFIG.Operating_Mode_A READ_FIRST CONFIG.Operating_Mode_B READ_FIRST \
    CONFIG.Enable_A Use_ENA_Pin CONFIG.Enable_B Use_ENB_Pin \
    CONFIG.Assume_Synchronous_Clk true \
    CONFIG.Register_PortA_Output_of_Memory_Primitives false \
    CONFIG.Register_PortA_Output_of_Memory_Core false \
    CONFIG.Register_PortB_Output_of_Memory_Primitives false \
    CONFIG.Register_PortB_Output_of_Memory_Core false \
    CONFIG.Load_Init_File true CONFIG.Coe_File [file join $tone_dir base_tone.coe] \
    CONFIG.Use_RSTA_Pin false CONFIG.Use_RSTB_Pin false]
set_property -dict $tone_desired [get_ips ltm_tone_bank]
foreach {key expected} $tone_desired {
    set actual [get_property $key [get_ips ltm_tone_bank]]
    if {$key eq "CONFIG.Coe_File"} {
        set actual [file normalize [file join [file dirname [get_property IP_FILE [get_ips ltm_tone_bank]]] $actual]]
        set expected [file normalize $expected]
    }
    if {![string equal -nocase $actual $expected]} {
        error "TONE_IP_READBACK_FAIL $key expected=$expected actual=$actual"
    }
}
generate_target all [get_ips ltm_tone_bank]
puts "TONE_IP_READBACK_PASS width=10 depth=1024 ports=2 read_latency=1"
