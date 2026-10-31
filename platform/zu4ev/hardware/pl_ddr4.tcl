# ZUMINI Rev C U31: one Micron 8 Gbit x16 DDR4 component (1 GiB).
# Source from the platform project before generating its IP output products.
# The schematic suffix is LY-075E; Vivado's catalog spells this LY-075.
if {[get_property PART [current_project]] ne "xczu4ev-sfvc784-2-i"} {
    error "pl_ddr4 requires the ZUMINI xczu4ev-sfvc784-2-i target"
}
if {[llength [get_ips -quiet pl_ddr4]] == 0} {
    create_ip -name ddr4 -vendor xilinx.com -library ip -module_name pl_ddr4
}
set_property -dict [list \
    CONFIG.C0.ControllerType {DDR4_SDRAM} \
    CONFIG.C0.DDR4_MemoryType {Components} \
    CONFIG.C0.DDR4_MemoryPart {MT40A512M16LY-075} \
    CONFIG.C0.DDR4_DataWidth {16} \
    CONFIG.C0.DDR4_DataMask {DM_NO_DBI} \
    CONFIG.C0.DDR4_Ecc {false} \
    CONFIG.C0.DDR4_TimePeriod {1250} \
    CONFIG.C0.DDR4_InputClockPeriod {10000} \
    CONFIG.C0.DDR4_PhyClockRatio {4:1} \
    CONFIG.System_Clock {No_Buffer} \
    CONFIG.C0.DDR4_AxiSelection {true} \
    CONFIG.C0.DDR4_AxiDataWidth {128} \
    CONFIG.C0.DDR4_AxiAddressWidth {30} \
    CONFIG.C0.DDR4_AxiIDWidth {4} \
    CONFIG.C0.DDR4_AxiNarrowBurst {false} \
] [get_ips pl_ddr4]
# c0_sys_clk_i takes the board's 100 MHz clock after the shared IBUFDS.
# c0_ddr4_ui_clk is 200 MHz at this memory period and 4:1 PHY ratio.
# Hold traffic reset until !c0_ddr4_ui_clk_sync_rst AND
# c0_init_calib_complete; c0_ddr4_aresetn is active low on ui_clk.
