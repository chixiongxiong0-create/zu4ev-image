# Current status - 2026-11-05

Full platform route and RAM board tests have now passed; see [BOARD_TEST.md](BOARD_TEST.md) for measured VCU/USB results and CPU savings. The entries below are chronological implementation records; their earlier integration-outstanding statements describe that stage only.

# NV12 DDR verification — 2026-11-04

Vivado/XSim 2025.1, xczu4ev-sfvc784-2-i. No subagents used.

Reproduce simulation: tests/zu4ev/nv12/run.ps1. Six tops passed: tb, tb_full, tb_ddr, tb_ddr_full, tb_pool, tb_sink. Fixed random seed fedcba98 for AXI tests. The RTL sources compile as Verilog, the testbenches as SystemVerilog. Results are under build/nv12_validation.

- Converter: directed pixels, markers, completion, stalled output abort/reset and two full-resolution frames with random bubbles.
- Writer: 34x6 (partial 128-bit row tails) and 1280x1024; two different buffer addresses; independent byte DDR scoreboard; stride padding sentinel; 4KiB boundary; random AW and W stalls; delayed B; no result while writes/responses outstanding; AW/W payload stability; result backpressure; abort before B; invalid descriptor; BRESP SLVERR and next-frame recovery.
- Pool: two configured slots, overlap rejection, stable descriptor and consumer offers under stalls, no overwrite of HELD slots, release and recycle, failed result recycle, invalid release.
- Sink: 1280x1024 YUY2 source -> converter -> pack FIFOs -> modeled DDR. Compare Y and vertically rounded UV against independent byte equations, two buffers; no-descriptor drop; long DDR stall forcing overflow; next frame recovery. The reference matches the A53 algorithm but does not execute NEON or validate cache coherence.

Synthesis reproduction: vivado -mode batch -source tests/zu4ev/nv12/synth.tcl. Top nv12_isp_ddr_sink, default 1280x1024, 256-beat FIFO per plane. Out-of-context 5ns clock: 1258 LUT, 834 FF, 4 BRAM tiles, 0 DSP; setup WNS +1.389ns, TNS 0, no failing setup endpoints. Reports: build/nv12_burst_synth/{utilization,timing}.rpt. Pool is not included in these resource numbers. HD.CLK_SRC is unspecified, external IO delays are not constrained, and no placement/routing was performed; this is not system timing signoff.

Remaining integration: connect pool descriptor/result channels to sink; tap actual final ISP YUY2 stream; connect 128-bit AXI master through the PS interconnect with required ID/cache/protection attributes; add configuration/IRQ/software access and physical DMA mappings; submit completed NV12 directly to VCU and release only after its input DQBUF. Neither camera_top nor boot images were enabled/changed for this path in this step. Arbitrary unbounded DDR stalls necessarily drop frames. Geometry parameters must be positive even values; FIFO depth must be power-of-two and >=32. Coordinated AXI/VCU reset is required for reset during ownership.


Managed-output addition: nv12_capture_output combines the tested pool/sink. tb_capture passed at 1280x1024 with randomized AXI stalls and byte-addressed DDR comparison. It configures two disjoint buffers, delivers both, feeds a frame while both are consumer-held (must drop), releases slot zero, then verifies reuse, frame metadata and level IRQ acknowledgment. This wrapper is not included in the earlier synthesis figures. run.ps1 includes this seventh test. AXI-Lite, BD, device-tree and driver integration are still outstanding.


AXI-Lite addition: tb_regs passed against the actual buffer pool, covering AW-before-W and W-before-AW, byte strobes, held B/R responses, reserved-slot configuration rejection, overlap error propagation, invalid commands/addresses/read-only writes, empty TAKE, invalid RELEASE, and normal frame metadata/TAKE/RELEASE. nv12_capture_peripheral elaborated with every real child module. tb_peripheral passed at 1280x1024: configuration only via AXI-Lite, two-buffer capture and byte comparison, held-buffer drop, metadata reads, IRQ acknowledgment, consumer release and buffer reuse. The new register/peripheral tops have not been synthesized and are not covered by the earlier sink timing report. run.ps1 includes both new tests (nine total); the new tests were individually executed after addition, not as a new complete nine-test regression.


Safe-stop addition: ABI version 2 introduces reset-disabled ENABLE, same-cycle-priority STOP, and STATUS.IDLE after writer/result/converter drain. tb_stop uses 1280x64, FIFO=32, seed fedcba98 and an external byte-addressed DDR model with stable-AW/W assertions. Passed blocked AW, blocked W, withheld B, full FIFO, simultaneous STOP/SOF, completed-frame retention, repeated STOP, premature ENABLE rejection, no accesses under continued source traffic after IDLE, and restart byte comparison in each blocked scenario. IDLE means PL DMA quiescence only; VCU ownership and retained pool mappings remain software responsibilities. The existing nine tests passed after the stop RTL changes; the unified runner now includes tb_stop as a tenth test. No post-change synthesis/route or board validation is claimed.

Additional directed checks passed: clearing CONTROL.ENABLE while waiting for B has the same drain guarantee as STOP; after re-enable, 100 cycles of mid-frame source traffic without SOF produce no DDR write before the next complete frame. Final directed transcript is build/nv12_validation/tb_stop_final.result.txt.

Unified ten-top regression completed successfully after the stop RTL changes (run.ps1 exit 0). The subsequent extra CONTROL-disable and mid-frame-restart assertions also passed in the final directed run.
