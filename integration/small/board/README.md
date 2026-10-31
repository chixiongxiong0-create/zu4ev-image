# 100 MHz board self-test with the original AE hardware preserved

The native ISP/AE master flow now defaults to the live Ibex firmware. See
[ISP_MASTER.md](ISP_MASTER.md) for the PS handoff utility, sensor ownership,
software packaging and build commands. The historical validation results below
remain evidence for their matching older images.

This flow snapshots the complete camera/AE source project into this repository's build tree. It appends an independent Ibex self-test and a JTAG AXI4-Lite master to the copied camera_top. Original PS, R5-facing AXI peripherals, MIPI, DDR4 and sensor interfaces remain in the copied design. No source in ZU4EV is edited. No firmware is replaced and no flash command is used.

The reference clock uses AE5/AF5 LVDS at 100 MHz (`constraints/pl_ddr4.xdc`, 10 ns). Existing `camera_clocks` generates `lite_clk` at 100 MHz, used by both Ibex and JTAG AXI. A configuration-initialized 256-cycle counter, asynchronously held reset until the clock MMCM locks, releases reset, then a two-stage synchronizer releases CPU reset. VIO probe_out0 can hold the CPU in reset; probe_in0 reports {bus alert, internal alert, minor alert, sleep}. VIO does not reset the camera/PS pipeline. VIO now resets only the CPU and CPU routing state; RAM AXI and accepted ISP configuration transfers drain under the shared global reset. An accepted ISP write may complete after CPU reset. Configuration and statistics use the real ISP register path with explicit PS/Ibex ownership; see [ISP_CONFIG.md](ISP_CONFIG.md). RAM contents persist across CPU reset, so an existing signature alone cannot prove a second execution.

Prepare once from a clean destination:

```
python integration/small/board/prepare_ae_copy.py
```

In Vivado MCP, source `integration/small/board/build_ae_board.tcl`, then launch/wait synth_1, launch/wait impl_1 through write_bitstream. Inspect routed timing, resource and DRC reports before programming. The source snapshot manifest describes original files; the copied camera_top, isp.v and isp_capture_frontend.sv receive the integration and narrow register-reset connections defined in prepare_ae_copy.py.

Temporary full PL programming interrupts existing camera/AE data flow, even though the copied design preserves the same interfaces. Running R5 software is not reloaded or restarted by this flow, so peripheral state may need recovery in the application. AE firmware equivalence is not established by this CPU self-test. QSPI contents are untouched; reboot restores the existing boot image.

After programming the copied camera_top.bit with matching .ltx, source `read_signatures.tcl` via Vivado MCP. It checks CPU-written signature 0x600d600d at 0x00200010, byte-enable result 0xabcd5578 at 0x00200000 and last-word pattern 0xdeadbeef at 0x0023fffc. This establishes CPU firmware execution, including its internal checks and two expected traps; it does not establish AE migration or live sensor equivalence.

For the validated ISP image, select `build/ibex_small/board_validation/board_validation.mem` through `IBEX_BOARD_ROM` when configuring a fresh copy. Its mailbox protocol and signatures are described in [board_validation/README.md](../board_validation/README.md); use `read_validation.tcl` and its `check_boot`, `pause`, `sample`, and `status` procedures for readback. The self-test signatures above belong to the matching self-test firmware.

The 2026-10-30 board run passed URAM firmware execution, two consistent firmware publications with advancing real statistics/FE/SOF, controlled shadow-black write/read/restore (`52 -> 53 -> 52`, signature `600dcf01`), and CPU-only VIO reset followed by fresh execution. Final ownership returned to PS and Ibex resumed read-only observation. Original LTM/TNR settings were restored; a historical TNR fault count remained at one without increasing during the recovery observation. See the [board validation evidence](../../../build/ibex_small/board_reports/20261029_uram_hardware/BOARD_VALIDATION.md). DP was disconnected and AE closed-loop behavior was not tested. Two later full checkpoint/project report-and-bit-generation replays both had zero critical warnings; the original 214-critical-warning summary could not be reproduced and its historical impact remains unclassified. See [CRITICAL_WARNING_REVIEW.md](../../../build/ibex_small/ae_board_uram_validation_20261029/reports/final_uram/CRITICAL_WARNING_REVIEW.md).


## Memory implementation and resource evidence

The board copy now selects both `RamPrimitive="ultra"` and `ProgramPrimitive="ultra"`: separate 256 KiB data and program stores use XPM true-dual-port UltraRAM with one-cycle reads. Instruction fetch/loader use program port A; CPU constant reads use B. The reusable system keeps both defaults at `"block"`. UltraRAM uses `no_change` on both ports; write-response data is unused. Same-word CPU data writes stall AXI AR.

UltraRAM cannot retain firmware initialization in the bitstream. A compact initialized BRAM boot store copies the selected image into program UltraRAM and zero-fills the remaining 65536-word address range. CPU and firmware loader stay reset until all 131072 copy cycles finish (1.31072 ms at 100 MHz). A global reset repeats copying; CPU-only VIO reset preserves the program image, including later loader writes. `build_ae_board.tcl` validates every dense hexadecimal input word, rejects empty/oversized/invalid images, removes only the all-zero tail, and emits exactly `IBEX_BOARD_BOOT_WORDS` words in `board_rom.mem`. Thus no nonzero image word is discarded. Current board-validation firmware uses 251 boot words; the default AE fixture uses 964. The compile-time `BootImageWords` must match a manually supplied compact image if bypassing that build script.

The halted firmware loader can overwrite and read program UltraRAM after initialization when `EnableFirmwareLoader` is enabled. The board wrapper does not enable or connect a PS firmware loader; adding the PS bridge remains future integration work. This change provides storage and loader semantics, not a new PS connection.

The actual part property ULTRA_RAMS is 48. get_sites enumerates 64 physical URAM sites, including unavailable resources, so site count is not the device resource budget. Focused XSim with the actual UltraRAM XPM passed CPU/native/AXI regressions at 2170 ns. The complete routed design with program and data UltraRAM uses 95/128 BRAM and 36/48 URAM; the two Ibex stores account for 32 URAM (16 program, 16 data), and the 251-word boot store uses one RAMB18. Routed WNS is +0.113 ns and WHS +0.010 ns, with TNS/THS zero. The board-validation program has booted from UltraRAM with its heartbeat advancing and errors zero. ILA depths are preserved. These results do not constitute full signoff: the 214-critical-warning summary and missing I/O constraints remain unresolved; see the [board validation evidence](../../../build/ibex_small/board_reports/20261029_uram_hardware/BOARD_VALIDATION.md).

An earlier all-BRAM attempt failed placement DRC: the fully linked design needed 188 RAMB36E2 versus 128 available. The initial top-only synthesis report excluded OOC IP contents and was not a valid full-system resource estimate. No such failing design was programmed. Future firmware growth changes ROM implementation resource use, so repeat full linked resource and timing checks for every new ROM image; 256 KiB logical address capacity does not guarantee a dense 256 KiB image fits alongside all AE IP.

## Camera recovery after volatile PL reconfiguration

Hot PL reconfiguration can leave the sensor streaming while the replacement CSI/D-PHY pipeline starts. The observed failure had sensor `0100=1`, all ten mode registers matching the FSBL values, but CSI packet/frame and AXIS counters staying zero. Recreating the FSBL standby/startup window restored capture without rewriting the sensor mode table. This supports the startup-window explanation; no physical LP11 waveform was measured.

Use the fixed-address PS hard-IIC0 helper described in [ps_iic_probe_preflight.md](../tools/ps_iic_probe_preflight.md), not the old GPIO-bit-banging `sensorctl`, which is incompatible with this connection. The helper requires exclusive IIC0 ownership, a live reference clock and released reset, and an initialized idle master with valid divisors. Its read-only CRL preflight checks clock-enable/reset state before IIC0 access; it does not enable clocks or release resets. If temporary reference-divider/master initialization is needed, establish it from the actual board clock source, retain the original clock/controller state, and restore it after the sequence. Do not apply one board's raw register constants to another board. State commands require the complete historical board-observed ID `0130` and a stream value of 0 or 1; this guard is not manufacturer identity authentication.

With the hardware owner controlling the original FSBL pipeline GPIO mapping, the successful sequence was:

1. Stop the capture bridge cleanly and confirm it has released capture ownership.
2. Run `ps_iic_probe_state_guard_aarch64 --clock-confirmed mode-probe` to read ID, stream and the fixed ten mode registers. Run `... --clock-confirmed standby` and confirm `0100=0` readback.
3. Drive the original FSBL pipeline request through `0` then `1`; wait for initialization/lite readiness and check no bus error. Request `3` and wait for video reset release.
4. Keep the sensor in standby for 10 ms after video release, exceeding the original FSBL minimum 2 ms intended to let the D-PHY observe idle/LP11. Request `7` to enable capture.
5. Run `... --clock-confirmed stream-on` and confirm `0100=1` readback. Restore temporary PS IIC clock/controller changes and restart the bridge.

The numbers `0/1/3/7` above identify this design's existing FSBL pipeline requests, not portable GPIO register writes. The [board validation report and execution evidence](../../../build/ibex_small/board_reports/20261029_uram_hardware/BOARD_VALIDATION.md) record the board-specific controls and results. After recovery, capture counts advanced `119 -> 239 -> 359` with invalid count zero, approximately 120 fps; ISP frames/statistics validity and CSI packet/frame counting resumed. Only sensor `0100` state changed. DP remained disconnected, so this does not validate display output or complete AE migration. Shadow configuration and CPU-only VIO-reset validation must be assessed separately from this recovery result.
