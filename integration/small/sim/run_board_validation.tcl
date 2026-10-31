set repo {E:/workspace/AI_Projects/RISC_V/ibex}
set platform {E:/workspace/AI_Projects/ZU4EV/zynq-zu4ev_platform}
set base $repo/integration/small
create_project -force board_validation $repo/build/board_validation -part xczu4ev-sfvc784-2-i
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]
set_property source_mgmt_mode None [current_project]
set f [open $base/sources.txt r]
foreach rel [split [read $f] "\n"] {if {$rel ne "" && ![string match */prim_xilinx/rtl/prim_clock_gating.sv $rel]} {add_files $repo/$rel}}
close $f
add_files $base/board/prim_clock_gating_ultrascale.sv
add_files [glob $base/rtl/*.sv]
add_files $platform/isp/ltm/isp_axi_regs.sv
add_files $platform/isp/ae/ae_stats_raw10.sv
add_files $platform/rtl/sensor/ae_fe_event.sv
set_property include_dirs [list $repo/vendor/lowrisc_ip/ip/prim/rtl $repo/vendor/lowrisc_ip/dv/sv/dv_utils] [current_fileset]
set_property verilog_define {SYNTHESIS FPGA_XILINX} [current_fileset]
add_files -fileset sim_1 $base/sim/tb_board_validation.sv
add_files -fileset sim_1 $repo/build/ibex_small/board_validation/board_validation.mem
set_property file_type {Memory Initialization Files} [get_files board_validation.mem]
set_property top tb_board_validation [get_filesets sim_1]
set_property verilog_define {SYNTHESIS FPGA_XILINX} [get_filesets sim_1]
set_property xsim.simulate.runtime {5000us} [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation

