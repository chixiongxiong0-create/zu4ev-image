# Call in a project for xczu4ev-sfvc784-2-i before adding bilateral_layers.sv.
# PG058: simple dual-port common-clock RAM, A writes and B reads.
# Both optional B output registers are disabled: one synchronous read cycle.
set ip_name ltm_line_bram
if {![llength [get_ips $ip_name]]} {
    create_ip -name blk_mem_gen -vendor xilinx.com -library ip -module_name $ip_name
}
set desired [dict create \
    CONFIG.Memory_Type Simple_Dual_Port_RAM \
    CONFIG.Write_Width_A 20 CONFIG.Write_Depth_A 1024 \
    CONFIG.Read_Width_A 20 CONFIG.Read_Width_B 20 \
    CONFIG.Enable_A Use_ENA_Pin CONFIG.Enable_B Use_ENB_Pin \
    CONFIG.Assume_Synchronous_Clk true \
    CONFIG.Operating_Mode_A READ_FIRST \
    CONFIG.Register_PortB_Output_of_Memory_Primitives false \
    CONFIG.Register_PortB_Output_of_Memory_Core false \
    CONFIG.Use_Byte_Write_Enable false CONFIG.Use_RSTA_Pin false CONFIG.Use_RSTB_Pin false]
set_property -dict $desired [get_ips $ip_name]
foreach {key expected} $desired {
    set actual [get_property $key [get_ips $ip_name]]
    if {![string equal -nocase $actual $expected]} {
        error "IP_READBACK_FAIL $key expected=$expected actual=$actual"
    }
}
puts "IP_READBACK_PASS module=$ip_name width=20 depth=1024 memory=Simple_Dual_Port_RAM common_clock=true read_latency=1"
generate_target all [get_ips $ip_name]
