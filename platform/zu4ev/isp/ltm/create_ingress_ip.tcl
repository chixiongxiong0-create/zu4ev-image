# Broadcast input storage, synchronous SDP RAM, one-cycle read head.
create_ip -name blk_mem_gen -vendor xilinx.com -library ip -module_name ltm_ingress_bram
set ingress_desired [dict create \
 CONFIG.Memory_Type Simple_Dual_Port_RAM \
 CONFIG.Write_Width_A 22 CONFIG.Write_Depth_A 4096 \
 CONFIG.Read_Width_A 22 CONFIG.Read_Width_B 22 \
 CONFIG.Enable_A Use_ENA_Pin CONFIG.Enable_B Use_ENB_Pin \
 CONFIG.Assume_Synchronous_Clk true CONFIG.Operating_Mode_A READ_FIRST \
 CONFIG.Register_PortB_Output_of_Memory_Primitives false \
 CONFIG.Register_PortB_Output_of_Memory_Core false \
 CONFIG.Use_Byte_Write_Enable false CONFIG.Use_RSTA_Pin false CONFIG.Use_RSTB_Pin false]
set_property -dict $ingress_desired [get_ips ltm_ingress_bram]
foreach {key expected} $ingress_desired {
 if {![string equal -nocase [get_property $key [get_ips ltm_ingress_bram]] $expected]} {
  error "INGRESS_IP_READBACK_FAIL $key"
 }
}
generate_target all [get_ips ltm_ingress_bram]
puts "INGRESS_IP_READBACK_PASS width=22 depth=4096 read_latency=1"
