# Ibex ISP master and shared USB buffers

**Goal:** Continue the validated Ibex integration into a runnable ISP/AE controller, include the existing USB DMA-BUF implementation, and produce a newly verified bitstream without hardware access.

**Execution:** User explicitly authorizes unattended execution. Sol 6.1 owns implementation; Terra owns tests and FPGA builds. The controller reviews architecture and evidence. Preserve all existing uncommitted files. Work branch: `codex/ibex-isp-master-dmabuf-20261030`.

## Constraints

- Follow `rtl-design` for authored RTL; existing SystemVerilog remains SystemVerilog, with no imposed generator conversion.
- Keep the original ZU4EV source tree intact; integrate into a fresh isolated board copy.
- Preserve existing camera, capture, DP and USB interfaces unless the controller integration requires an explicitly documented extension.
- No hardware operations or flash changes; stop at bitstream and offline validation.
- Existing board observation tests are baseline evidence, not proof of an AE closed loop.
- USB uses the previously implemented shared DMA-BUF path. Do not add a redundant frame-copy DMA.
- No concurrent writes to the same files. Do not scan generated Vivado directories or read full logs/netlists.

## Deliverables and gates

- [x] Sol: inspect board source preparation, actual sensor pin routing, ISP ownership and existing AE scaffolding. Freeze the clock/reset, MMIO, I2C, ownership and firmware lifecycle contracts before RTL implementation.
- [x] Terra: run focused AE, ownership/CDC and USB baseline tests; identify available cross compilers and FPGA tools.
- [x] Sol: implement real sensor control and AE firmware, board handoff/startup integration, reproducible build and software packaging. Include the existing DMA-BUF software and preserve its diagnostics.
- [x] Terra: test normal AE convergence and register readback, NACK/timeout and stopped-frame failure, ownership transitions and CPU reset, open-drain behavior and repeated start, coherent statistics and relevant CDC/reset cases. Test USB source retention, completion ordering, stop/disconnect and failed submissions.
- [x] Controller: inspect requirements against changes and adjudicate any failures before the build.
- [x] Terra: build the complete linked FPGA project through routing, inspect timing/resource/DRC/CDC/route completeness and black boxes, then generate the bitstream and matching probes.
- [x] Controller: verify output paths, hashes, test evidence and limitations; deliver changed files and concise results.

## Review focus

1. Sensor bus must have one active owner; PS startup and Ibex AE must not drive it concurrently.
2. PS-to-Ibex configuration handoff must not interrupt a pending ISP commit or accepted bus transfer.
3. CPU reset must not abandon accepted writes or report a stale firmware success.
4. Sensor read/write failures and absent video must produce observable failures rather than false successful AE updates.
5. Shared frames must stay held until both DP and USB complete, including submission/stream-stop errors.

## Progress

- Read both referenced chats with `read_thread`. Confirmed prior firmware was observation/shadow-restore only and the USB implementation exists in the original platform software.
- Sol implementation agent dispatched for architecture discovery, initially read-only.
- Terra verification agent dispatched for independent baseline tests and build readiness.
- Initial git state: `.gitignore` modified; integration/docs and debug artifacts already untracked. No original changes discarded.
- Architecture is recorded in `docs/superpowers/specs/2026-10-30-ibex-isp-master.md`.
- Native sensor engine/CSR, safe pin mux, PS-visible RUN/stop-toggle acknowledgement, native AE firmware, runtime handoff utility and complete USB software source packaging are implemented for focused verification. CPU reset drains accepted sensor traffic before quiescence.
- Stale-quiescence and repeated-stop ABA defects were reproduced and fixed with stop request/acknowledgement and pending serialization. The initial firmware trap was traced to Ibex's fixed vectored MTVEC behavior and fixed by an aligned 32-entry jump table. The controller independently checked the core's MTVEC and IRQ PC logic.
- Real-CPU integration passed dark exposure increase, bright exposure decrease, first-byte stop with full write/readback drain and ownership reclaim, and sensor NACK failure. No-frame failure used explicit simulation timer acceleration; this checks control logic rather than elapsed physical time. Final leaf regression precedes the full build.
- Final candidate is `build/ibex_small/isp_master_v3_20261030`; manifest hashes match the frozen implementation. Its independent firmware build produces binary SHA-256 `93416bd99ccfe248069ee9afdf80dd3ea1326283a10c39ac6f109cff86ea5999`, identical to the source-tree build. Copy software tests and static AArch64 builds passed. Commands and limits are in `docs/verification/2026-10-30-isp-master-baseline.md`.
- Baseline reported by Terra: ISP ownership/CDC XSim passed; three AE host executables passed; nine USB/software tests passed. AArch64 static application cross build passed. RISC-V GCC 13.2.0 is available after sourcing `/mnt/d/development/rtl/env.sh`; Vivado 2025.1 is installed.
- Architecture approved for implementation: dedicated bounded sensor I2C engine and local CSR/timer, exclusive PS/Ibex pad mux, coherent existing ISP snapshots, and actual board AE firmware. PS-visible request/status registers must allow graceful quiesce before owner reclaim. Accepted I2C operations drain through STOP across CPU reset; new commands remain inhibited until rearm. The source platform remains unchanged.
- Full-build configuration completed through Vivado MCP session `vivado-20261030-103307-d31e0202`, PID 3684. Candidate `build/ibex_small/isp_master_v3_20261030`, part `xczu4ev-sfvc784-2-i`, top `camera_top`, formal ROM 1371 compact boot words, `general.maxThreads=1`, synthesis jobs=1. Target reports directory: candidate `reports/final`. Configuration exit 0; synthesis/implementation/bitstream remain pending. Terra owns this session; do not start a duplicate build.

## Final completion

The resumed Terra build reused successful synthesis and completed routed implementation and bitstream generation. Final state: `write_bitstream Complete!`, 100%, no refresh needed; bit generation reported 0 errors and 0 critical warnings. Routed setup/hold slack is +0.174/+0.010 ns, TNS/THS zero, 103163/103163 routable nets fully routed, routing errors zero and blackboxes empty. BRAM is 96.5/128; URAM 36/48.

All eight files in candidate `deliverables/SHA256SUMS` were independently hashed by the controller and match. `camera_top.bit` SHA-256 is `45739aa4e12954a3060acf23f4f36f4656c28e1e3e1464ca4d7d77cb474fac54`; the LTX was exported from the matching routed design. The source manifest remains unchanged and matched.

This completes the requested offline bitstream milestone, not full physical signoff. Missing external I/O delays, MIPI TIMING-24/28 warnings, DRC/CDC warnings and a request-payload shared-source bus-skew routing warning are retained in the verification report. Final reported CFG_REQUEST skew is MET, but shared-source logical-bit coverage remains a review item. No hardware or flash programming occurred.
