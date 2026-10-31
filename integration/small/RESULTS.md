# XSim 验证结果

2026-10-28，Windows Vivado/XSim 2025.1，目标器件 xczu4ev-sfvc784-2-i。

实际仿真输出：

```text
IBEX_MEMORY_PASS all_16_byte_masks boundaries errors reset
IBEX_SMALL_PASS signature=600d600d reads=5 writes=6 errors=2
$finish called at time : 1460 ns
```

运行证据：`build/ibex_small/xsim/ibex_small.sim/sim_1/behav/xsim/simulate.log`。
CPU 的两个错误响应为预期的越界load和ROM写异常，已由机器模式异常处理验证原因。
存储测试遍历全部16种字节掩码。未执行综合、布局布线、时序分析或上板。
上游仿真存在 timescale 与 decoder enum 类型警告；本次功能测试通过，
未进行上游源码修复或覆盖率闭合。仿真定义 SYNTHESIS 禁用了上游SVA辅助检查，
验收依赖自检固件和显式检查，不能视为上游断言回归通过。


## XPM dual-port / AXI read extension (2026-10-28)

Vivado 2025.1 XSim compiled the actual `xpm.xpm_memory_tdpram` model with `-L xpm`, MEMORY_SIZE=2097152, common clock, read latency 1 on both ports, 8-bit byte writes. CPU small firmware and memory tests were rerun together with AXI tests.

Focused AXI coverage: first/last word, upper/lower range errors, unaligned read, R backpressure with stable data/response and blocked AR, AW-before-W and W-before-AW, B backpressure, rejected writes preserve RAM, concurrent CPU write/AXI read at different words, same-word CPU write blocks AR and subsequent read sees committed data. Original 16 byte-enable masks, ROM boundaries and errors, RAM retention across reset remain covered.

This verifies behavior only, not synthesis resource use, post-route timing, PS interconnect integration, CDC, cache coherency, or AE algorithm/firmware equivalence. No ZU4EV project files were edited. SYNTHESIS still disables upstream simulation-only helpers/SVA; this is not a full ISA/UVM regression.

Final batch `tools/run_xsim.ps1` completed successfully at 2026-10-28 19:55:05, simulation end 2170 ns:

```
IBEX_AXI_PASS boundaries alignment backpressure write_reject concurrency collision
IBEX_MEMORY_PASS all_16_byte_masks boundaries errors reset
IBEX_SMALL_PASS signature=600d600d reads=5 writes=6 errors=2
```

Evidence: `build/ibex_small/runner-console.log` and `build/ibex_small/xsim/ibex_small.sim/sim_1/behav/xsim/simulate.log`. Runner requires all three PASS tokens and rejects Fatal/Error.


## MiniZU ZU4EV actual board validation (2026-10-28)

A copied complete AE project preserves original PS/R5-facing peripherals, camera and DDR4 interfaces and both original ILA configurations. Original ZU4EV sources were checked against the snapshot manifest: 84 files unchanged. The copied top appends an independent Ibex self-test with JTAG AXI and reset VIO. No AE firmware was ported; no QSPI write or PS firmware reload was performed. Full PL reconfiguration temporarily interrupts the camera pipeline; continued R5 AE operation/equivalence was not verified.

RAM selects UltraRAM, preserving 256 KiB/32-bit/four byte enables/common clock/read latency1. Actual xczu4ev part property is48 URAMs; Ibex RAM maps to16. Full placed design uses127.5/128 BRAM tiles and20/48 URAMs, LUT48496/87840. All-BRAM attempt was rejected by full linked placement DRC (188/128 RAMB36); top-only synthesis utilization excludes OOC IP and must not be used as the system resource budget. Future ROM-image growth requires a new full resource/timing check.

The upstream Xilinx BUFGCE has a7SERIES SIM_DEVICE default. A local UltraScale+ binding fixes reproducible source builds without editing upstream RTL. The validated bitstream was generated from a documented equivalent post-route ECO replacing that cell at the same name/BEL with identical I/CE/O nets, CE mode and inversion settings, then route_design-preserve and full DRC/STA were rerun. No DRC was disabled. Source patch/ECO relationship and hashes are recorded in hardware_evidence.json.

Final reports: setup WNS+0.101ns, hold WHS+0.010ns, TNS/THS0; all95911 routable nets fully routed and0 routing errors;15 bus-skew constraints have minimum+4.440ns slack. Bitgen precondition DRC:0 errors. The actual core clock is clk_out2_camera_clocks with10.000ns period.

ROSS MCP programmed xczu4_0 through Digilent/210357A7D00EA; startup HIGH. Hardware discovery found2 original ILAs,1 MIG,1 added JTAG AXI and1 VIO. Actual JTAG reads:

```
0x00200010 = 0x600d600d  CPU PASS signature
0x00200000 = 0xabcd5578  CPU byte/halfword write result
0x0023fffc = 0xdeadbeef  last RAM word
IBEX_BOARD_PASS
```

The UltraRAM and local clock binding XSim regression also passes CPU/native/AXI tests at2170ns. See board/README.md for reproduction and reset limitations. Final artifacts and reports are in build/ibex_small/board_reports, including camera_top.bit, camera_top.ltx, camera_top_eco_routed.dcp, hardware_evidence.json, timing_summary.rpt, drc.rpt, route_status.rpt, bus_skew.rpt and utilization.rpt. The temporary test image is currently programmed; reboot uses the existing QSPI boot image.
