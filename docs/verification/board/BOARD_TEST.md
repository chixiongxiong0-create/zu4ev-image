# Board verification, 2026-10-31

## Before programming

- JTAG Digilent `210357A7D00EA`, devices `xczu4_0`, `arm_dap_1`; Vivado and hw_server 2025.1. Current original PL reported two ILA cores; no original probes were associated.
- XSDB target list: RPU Reset; both Cortex-R5 cores No Power; all four A53 Running. COM13 115200 root shell, Linux 6.12.0, bridge PID 186, capture module loaded and DP connector connected.
- V3 bit SHA-256 `45739aa4e12954a3060acf23f4f36f4656c28e1e3e1464ca4d7d77cb474fac54`; LTX `6155de4d889944cbf5c8795ad30be6ad5025a4439d28327e1ea49cfa11069952`.
- Old PL ISP reads: ID 49535031, capabilities 0000001f, +0c 00000006, black 52, gain 96; +210=5, +214/+218=00013547, +21c=00000110. Attempted +248 generated AXI AP transaction error; a new DAP connection successfully re-read CRL and GPIO. Old register map differs; values above are raw, not evidence of v3 AE.
- Initial IIC0 REF 01000500, reset 0001fffc, IOPLL_CTRL 00015a00, FRAC 0, PLL_STATUS 1b. With R5 off and no IIC0 Linux driver, reset bit9 alone released (0001fdfc); CR/SR/SIZE=0, IMR=2ff; temporary REF=01010500 and CR=ad0e. Verified transferred read-only probe SHA `16a2d4622b16b5a1a1e6937ffdc6981ef7e50d343e529eab998795e1b49fcdae`. Probe preflight passed but first TX timed out; no sensor register was read or written. Probe restored CR=ad0e, SR=0, IMR=2ff. REF and CR restored to 01000500/0, and reset bit9 restored to original 0001fffc. Sensor baseline remains unknown; old PL routing must not be inferred from the new RTL.

## Volatile v3 programming and video recovery

- Stopped original bridge PID186 with SIGTERM; driver reported ch0=62597/errors0, ch1=62595/errors0/miss_delta1, late0. Capture module refcount0 and `rmmod` succeeded. Downloaded matching v3 bit+ltx via Vivado MCP; startup HIGH, 2 ILA, 1 AXI, 1 VIO, VIO alerts and sleep0. No flash programming.
- Real Ibex boot mailbox magic 49414531, WAITING=1, fault0, heartbeat 0beb9590 to 0bf30020 in 100ms; session/signature initially zero.
- V3 ISP ID49535031/caps ff, PS owner0/RUN0. Sensor probe with v3 IIC routing returned ID0130, stream1, all ten mode bytes matched prior FSBL mode, VTS0211, exposure20d0, 3e03=0a, gain_hi02, gain20. Changed only sensor 0100 from1 to0 and read back; used existing request sequence0/1/3/7 with 10ms standby interval, then wrote0100=1 and read back. Restored IIC CR0 and REF01000500; reset remains released for handoff. ISP frame 0x77b to 0x7f4 in about one second, valid=5.
- Reinserted capture driver and launched v3 shared-buffer bridge PID286 in /tmp. Capture 117 to1077 and DP flips106 to1066, invalid0 over about8 seconds. Original ISP/TNR startup script completed once: memtest_errors0, calibrated1/history_valid1, ISP pending0, TNR fault count1. It was no longer running before handoff.

## Live Ibex AE and ownership

- `board_handoff start --ps-writers-stopped` exit0: owner1/run1/grant1/armed1. Mailbox state3, signature600dae01, fault/mcause/mepc0. IRQ advanced 0x6cc to0x7c4 over two seconds; records advanced 0x6ce to0x7c6. Exposure fell from pre-handoff 20d0 to0930, gain20, mean98; changes5. Firmware checks each sensor write by readback.
- `board_handoff stop` exit0 returned owner0/run0/quiescent1/grant0. Attempting independent PS sensor readback was refused before writing because PS IIC SR=0xa0 did not satisfy strict FIFO-empty precondition. No FIFO was cleared. Restart succeeded, session2, owner1/run1.
- User covered and uncovered the lens. Non-atomic one-second samples in `ae_light_observations.txt`: 07:56:02 mean98/exposure0970/gain20; 07:56:03 mean4/exposure20d0/gain3f; 07:56:04 mean97/exposure0b00/gain20. At 07:56:11-12 mean4/exposure20d0/gain3f, at 07:56:14 mean102/exposure0cd0/gain20 and by 07:56:15 exposure0bb0. Changes 0x1a to0x42; state3/fault0 throughout. Separate fields are sampled sequentially, not atomically.

## USB/DP live observation

- Windows enumerated UVC Camera VID1d6b/PID0102. FFmpeg DirectShow YUY2 1280x1024 120fps 10 seconds exited0 with1199 frames. V3 bridge reported `USB buffer mode=shared DMA-BUF`. During the run, capture and DP continued approximately120fps, invalid0; source-side cumulative drop9, and sent113→1193 / returned112→1192.
- The bridge did report three buffer errors during the first sustained stream, before STREAMOFF: V4L2 flags4040, bytesused0, count1→3, while owner/dq/event/send errors remained0. A second STREAMON was observed later from an unknown host client; buffer errors continued there. Do not characterize this as error-free or attribute it solely to normal STREAMOFF. Root-cause investigation is ongoing. Gadget config maxpacket3072/maxburst15/interval1. Image integrity, USB reconnect behavior and CPU reduction were not measured.

## Last observed state

At 07:59:13, real Ibex state3/fault0/signature600dae01/session2, IRQ a5c1, records a5c2, mean90, exposure0180, gain20, changes98. Latest handoff status owner1/run1/grant1/armed1/fault0, bridge PID286 running and DP flips continuing. XSDB still shows RPU Reset and R5 cores No Power; all four A53 Running. These observations are snapshots and not atomic across interfaces. Temporary PS IIC reset release remains in effect while Ibex owns the bus; no flash or boot image was changed.

## Final refresh at 2026-10-31 08:02:44 (Asia/Shanghai)

- Ibex mailbox: state3, heartbeat7cfc8293, fault0, IRQ10888, FE13a56, mean96, exposure0ab0, gain20, changes186, records1088a, session2, signature600dae01. Values are hexadecimal except mean96; fields were read sequentially.
- Handoff readback: owner1/run1/grant1/armed1/fault0, busy0, quiescent0, SCL/SDA high. PID286 v3 bridge continues; latest counters capture75721, invalid0, DP flips75710, drop11, USB sent28532/returned28531, buffer errors65, USB owner/DQ/event/send errors0. The second USB client was not started or stopped by this test. RPU Reset, R5 #0/#1 No Power; all A53 cores Running.
- The bounded target log including both STREAMON events, first STREAMOFF, per-second parallel capture/DP counters, and sampled buffer errors is `usb_target_excerpt.txt`. In the first FFmpeg stream, errors arose before STREAMOFF. Linux source review indicates the observed zero-byte error buffer is consistent with UVC DROP_INCOMPLETE after an isochronous request status such as -EXDEV, but no target trace established the underlying request status; do not treat this as a confirmed root cause. Debugfs was not mounted and dynamic debug was not changed. Additional USB diagnosis remains outstanding.
