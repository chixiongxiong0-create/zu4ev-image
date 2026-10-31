# TNR stream queue: common-clock simple dual-port, one synchronous read cycle.
if {![llength [get_ips -quiet tnr_stream_bram]]} {
    create_ip -name blk_mem_gen -vendor xilinx.com -library ip -module_name tnr_stream_bram
}
set_property -dict [list \
    CONFIG.Memory_Type Simple_Dual_Port_RAM \
    CONFIG.Write_Width_A 34 CONFIG.Write_Depth_A 16384 \
    CONFIG.Read_Width_A 34 CONFIG.Read_Width_B 34 \
    CONFIG.Enable_A Use_ENA_Pin CONFIG.Enable_B Use_ENB_Pin \
    CONFIG.Assume_Synchronous_Clk true CONFIG.Operating_Mode_A READ_FIRST \
    CONFIG.Register_PortB_Output_of_Memory_Primitives false \
    CONFIG.Register_PortB_Output_of_Memory_Core false \
    CONFIG.Use_Byte_Write_Enable false CONFIG.Use_RSTA_Pin false CONFIG.Use_RSTB_Pin false \
] [get_ips tnr_stream_bram]
if {![llength [get_ips -quiet tnr_axi_clock_converter]]} {
    create_ip -name axi_clock_converter -vendor xilinx.com -library ip -module_name tnr_axi_clock_converter
}
set_property -dict [list CONFIG.PROTOCOL AXI4 CONFIG.ADDR_WIDTH 32 \
    CONFIG.DATA_WIDTH 128 CONFIG.ID_WIDTH 4 CONFIG.ACLK_ASYNC 1 \
    CONFIG.SYNCHRONIZATION_STAGES 3] [get_ips tnr_axi_clock_converter]
generate_target all [get_ips {tnr_stream_bram tnr_axi_clock_converter}]
