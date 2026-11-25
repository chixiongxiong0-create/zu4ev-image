# ZU4EV Dynamic DPC RTL Implementation Plan

**Goal** — Implement and verify optional, online, dual-pixel Mono RAW10 defect correction in the existing ZU4EV capture frontend.

**Architecture** — Four rotating synchronous line RAMs form 3×3 windows for two pixels per clock. A pipelined two-lane kernel identifies outliers and a wrapper manages frame-atomic configuration and counters.

**Tech stack** — Existing SystemVerilog and Vivado 2025.1 XSim.

**Spec** — `platform/zu4ev/isp/dpc/DYNAMIC_DESIGN.md`.

## Scope

- Work in the existing `codex/zu4ev-ffc-dpc` checkout. Follow `AGENTS.md`. Preserve pre-existing working files and changes. Implement sequentially. Do not commit, push, deploy, program the board, or change QSPI.
- Use Brigates only as an algorithm reference. Do not import its RTL or RAM libraries. Keep the existing static DPC and its address/behavior contract.
- Design for WIDTH even, 4..2048 and HEIGHT 3..1024. Defaults 1280×1024. The frontend wires through unsupported geometries and legacy configurations. All existing external frontend ports are retained.
- Add a compile-time `DYNAMIC_DPC` parameter, default 1, at the end of the frontend parameter list. Set 0 only for explicit compatibility/test instances whose source manifests cannot include the dynamic RTL, or to preserve the legacy low-latency path where required. When compiled in, reset selects same-latency pixel-exact bypass.
- Track complete rows independently of input bubbles. Do not rely on blanking, downstream ready, or a subsequent frame to drain. Use local synchronous RAM inference with no RAM reset and no extra generated IP.

## Task 1 — Two-pixel window and correction

- [x] Create `platform/zu4ev/isp/dpc/dpc_dynamic_window.sv`. Accept existing 20-bit even/odd packing plus valid, SOF/EOL and fault flags. Use four independent WIDTH/2×20 line banks and synchronous registered reads. Carry center pixels, two packed 3×3 windows or equivalent shared taps, lane interior mask and aligned SOF/EOL/EOF, with no ready.
- [x] Read each center row as soon as it and its required same-frame neighbor rows are complete. Write and read concurrently. Keep bank ownership across frame boundaries, invalidate old tags on bank reuse and never read across frames. Pipeline read metadata and process the last pair without consuming a phantom sample. Immediately adjacent frames and final-frame idle drain are mandatory.
- [x] Create `platform/zu4ev/isp/dpc/dpc_dynamic_kernel.sv`. Implement the three pipeline stages in the spec, strict unsigned widened comparisons, inclusive flatness gate, and the documented direction tie order. Exclude the center from neighbor min/max. Border lane pass-through is bit-exact. Never use repaired pixels as neighbors.
- [x] Add `tests/zu4ev/dpc/tb_dpc_dynamic.sv` with an independent frame/coordinate-based integer reference model. Cover both lane parities, edges/corners, all directions and ties, flatness equality, threshold equality/one beyond, values 0/1023 and margins 1023, isolated real lights, textured/step-edge patterns, hot/cold clusters, contiguous and bubbled frames, EOF drain, reset/fault/resync. Check metadata and emitted counts independently.

## Task 2 — Frame configuration and normal frontend integration

- [x] Create `platform/zu4ev/isp/dpc/dpc_dynamic_raw10.sv`, with the same stream signal names and 20-bit lane order as `dpc_raw10`. Add the existing synchronous 16-bit-address, 32-bit-data CSR request/response pattern. Commit configuration at the frame's first RAM read request. Ensure that earlier frame data already in the pipeline sees its own settings. Fault flush wins over commit and frame counter publication.
- [x] Use the register offsets in the spec, with ID ASCII DPCD (`0x44504344`). Mode bits [1:0] are 0 bypass, 1 observe, 2 repair, 3 invalid. Bits 2/3 enable hot/cold detection. Default shadow/active values are bypass, both detectors enabled, hot/cold margins 32 and flatness limit 24. Threshold word packs hot [9:0], cold [19:10], flatness [29:20]. Active-mode bit 8 reports pending. Reserved bits read zero and writes with nonzero reserved bits fail. While pending reject writes to the shadow and commit. Apply only a pre-existing pending configuration at the frame-start boundary. Retain pending across stream faults. Reset clears pending and counters. Successful AXI writes require full strobe and word alignment. Reads follow the existing single-cycle local response. Count one fault per fault event, not every cycle of a held fault.
- [x] Modify `platform/zu4ev/isp/isp_capture_frontend.sv` to insert dynamic after static and before both AE and BLC/LTM. Forward all stream metadata. Keep static probe behavior and CSR map. Keep FFC, static and dynamic CSR selection distinct. Modify `platform/zu4ev/isp/ltm/isp_axi_regs.sv` with a default-disabled feature parameter for decoding the new CSR range. Update applicable maintained source manifests and explicit simulation file lists. Inspect source manifests without scanning generated directories.
- [x] Add dynamic checks to the core test and add or extend AXI integration tests to cover address selection, actual dynamic modes, AW/W order, response stalls, rejected writes and configuration across contiguous frames. Preserve existing test coverage. Include two different pending/apply configurations across adjacent frames to exercise frame configuration isolation.

## Task 3 — Verification and handoff

- [x] Add a focused PowerShell XSim runner, supporting quick and 1280×1024 runs. Use deterministic seeds and clear PASS/fatal criteria. Run quick and full dynamic tests, frontend AXI integration, existing static DPC core/probe/AXI tests, and `git diff --check`. Report each command, exit result and relevant PASS lines. No full hardware build is required for this handoff.
- [x] Review critical cases before returning. Verify write/read bank exclusion for continuous back-to-back frames and after gaps, EOL drain while accepting the next line, fault while prior data remain in flight, high threshold width, and bit-exact bypass/observe. Report deviations, test limitations, estimated rather than measured BRAM/timing, and remaining board checks.
- [x] Final response in Chinese. List files actually changed, test evidence, blockers and unresolved risks. Preserve the working tree for Codex review.
