# Extend the existing 200 MHz capture/DP block design with encoder-only VCU.
# Source after ps_system.tcl. No external wrapper ports are changed.
if {[llength [get_bd_cells -quiet vcu]]} { error "VCU already exists" }
set_property -dict [list CONFIG.NUM_MI 9 CONFIG.NUM_CLKS 2] [get_bd_cells control_xbar]
set_property CONFIG.NUM_SI 6 [get_bd_cells memory_xbar]
set_property CONFIG.NUM_PORTS 8 [get_bd_cells irq_concat]
create_bd_cell -type ip -vlnv xilinx.com:ip:vcu:1.2 vcu
set_property CONFIG.ENABLE_DECODER false [get_bd_cells vcu]
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 vcu_refclk
set_property -dict [list CONFIG.PRIM_IN_FREQ 200.000 CONFIG.CLKOUT1_REQUESTED_OUT_FREQ 33.333 CONFIG.NUM_OUT_CLKS 2 CONFIG.CLKOUT2_USED true CONFIG.CLKOUT2_REQUESTED_OUT_FREQ 100.000 CONFIG.USE_RESET false CONFIG.USE_LOCKED false] [get_bd_cells vcu_refclk]
connect_bd_net [get_bd_ports video_clk_in] [get_bd_pins vcu_refclk/clk_in1] [get_bd_pins vcu/m_axi_enc_aclk] [get_bd_pins vcu/m_axi_mcu_aclk]
connect_bd_net [get_bd_pins vcu_refclk/clk_out2] [get_bd_pins vcu/s_axi_lite_aclk] [get_bd_pins control_xbar/aclk1]
connect_bd_net [get_bd_pins vcu_refclk/clk_out1] [get_bd_pins vcu/pll_ref_clk]
connect_bd_net [get_bd_ports video_resetn_in] [get_bd_pins vcu/vcu_resetn]
connect_bd_net [get_bd_pins vcu/vcu_host_interrupt] [get_bd_pins irq_concat/In7]
connect_bd_intf_net [get_bd_intf_pins control_xbar/M08_AXI] [get_bd_intf_pins vcu/S_AXI_LITE]
foreach {master slave} {M_AXI_ENC0 S03_AXI M_AXI_ENC1 S04_AXI M_AXI_MCU S05_AXI} {
    connect_bd_intf_net [get_bd_intf_pins vcu/$master] [get_bd_intf_pins memory_xbar/$slave]
}
assign_bd_address -offset 0xA1000000 -range 0x00100000 -target_address_space [get_bd_addr_spaces ps/Data] [get_bd_addr_segs vcu/S_AXI_LITE/Reg] -force
foreach space {vcu/EncData0 vcu/EncData1 vcu/Code} {
    assign_bd_address -offset 0 -range 0x80000000 -target_address_space $space [get_bd_addr_segs ps/SAXIGP2/HP0_DDR_LOW] -force
}
validate_bd_design
save_bd_design

source [file join [file dirname [info script]] vcu_clock_metadata.tcl]
