# Source after add_vcu.tcl in the isolated NV12 project.
if {[llength [get_bd_intf_ports -quiet NV12_CTRL]]} {error "NV12 already added"}
set_property CONFIG.NUM_MI 10 [get_bd_cells control_xbar]
set_property CONFIG.NUM_SI 7 [get_bd_cells memory_xbar]
set ctrl [create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 NV12_CTRL]
set_property -dict [list CONFIG.ADDR_WIDTH 32 CONFIG.DATA_WIDTH 32 CONFIG.FREQ_HZ 200000000 CONFIG.PROTOCOL AXI4LITE] $ctrl
set mem [create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 NV12_MEM]
set_property -dict [list CONFIG.ADDR_WIDTH 32 CONFIG.DATA_WIDTH 128 CONFIG.FREQ_HZ 200000000 CONFIG.PROTOCOL AXI4 CONFIG.READ_WRITE_MODE WRITE_ONLY CONFIG.ID_WIDTH 0 CONFIG.MAX_BURST_LENGTH 16 CONFIG.NUM_WRITE_OUTSTANDING 1] $mem
connect_bd_intf_net $ctrl [get_bd_intf_pins control_xbar/M09_AXI]
connect_bd_intf_net $mem [get_bd_intf_pins memory_xbar/S06_AXI]
set clock [get_bd_ports video_clk_in]
set buses [get_property CONFIG.ASSOCIATED_BUSIF $clock]
set_property CONFIG.ASSOCIATED_BUSIF "${buses}:NV12_CTRL:NV12_MEM" $clock
set_property CONFIG.PSU__USE__IRQ1 1 [get_bd_cells ps]
create_bd_port -dir I -type intr nv12_irq
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 nv12_irq_concat
set_property CONFIG.NUM_PORTS 8 [get_bd_cells nv12_irq_concat]
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 nv12_irq_zero
set_property -dict [list CONFIG.CONST_WIDTH 1 CONFIG.CONST_VAL 0] [get_bd_cells nv12_irq_zero]
connect_bd_net [get_bd_ports nv12_irq] [get_bd_pins nv12_irq_concat/In0]
for {set i 1} {$i<8} {incr i} {connect_bd_net [get_bd_pins nv12_irq_zero/dout] [get_bd_pins nv12_irq_concat/In$i]}
connect_bd_net [get_bd_pins nv12_irq_concat/dout] [get_bd_pins ps/pl_ps_irq1]
assign_bd_address -offset 0xA0080000 -range 0x00010000 -target_address_space [get_bd_addr_spaces ps/Data] [get_bd_addr_segs NV12_CTRL/Reg] -force
assign_bd_address -offset 0 -range 0x80000000 -target_address_space [get_bd_addr_spaces NV12_MEM] [get_bd_addr_segs ps/SAXIGP2/HP0_DDR_LOW] -force
validate_bd_design
save_bd_design
