# Integrated NV12 hardware output

Current board configuration taps the final ISP/TNR output, writes four NV12
slots in PS DDR, and exports them through Linux DMA-BUF to the VCU H.264
encoder. A53 raw-frame conversion is bypassed. Control is at 0xA0080000,
ABI v2; ENABLE/STOP/IDLE and VCU input ownership are required.

See [LINUX_VCU.md](LINUX_VCU.md) for build/runtime integration,
[REGISTERS.md](REGISTERS.md) for the register contract and
[BOARD_TEST.md](BOARD_TEST.md) for RAM-board results and remaining limits.
The verified RAM image was not flashed to QSPI. Build artifacts are local;
source scripts currently require the existing validated VCU base project and
kernel build described in LINUX_VCU.md, not a self-contained clean checkout.

The following sections describe individual module interfaces; their manual
connection notes are already implemented by nv12_capture_peripheral and the
platform adapter in the integrated configuration.

# ISP NV12 output micro-architecture
Input is a non-stallable ISP tap, little-endian Y0 U Y1 V, two pixels per valid cycle. WIDTH and HEIGHT must be positive even values. Synchronous active-low reset. One clock domain.

Independent 16-bit Y and UV outputs have valid/ready, SOF/EOL/EOF. Y emits every pair; UV emits one U,V pair on odd rows using (previous+current+1)>>1. Two independent one-entry output registers hold payload under stalls; one row of chroma storage is owned by this module. The converter itself has no DDR port; nv12_isp_ddr_sink combines it with the burst DDR writer. UV and Y are separate plane streams, not a contiguous NV12 byte stream.

Controller states are idle/active, encoded by active. SOF begins a frame; malformed geometry, input fault, or an occupied required output slot aborts the frame. frame_abort invalidates the entire destination buffer, including already transferred pixels. Pending outputs remain stable until accepted; restart is permitted only at a later SOF with available slots. frame_done means final output handshakes completed, not DDR write responses. Downstream must discard aborted frames and commit only after DMA completion. Input never backpressures the ISP or DP.

Counters advance only on accepted input; chroma RAM writes only on accepted even rows. RAM needs no reset since odd rows are reachable only after a complete even row. Output valid clears on handshake; payload is replaced only if its slot is free. Reset cancels all ownership. Latency one clock; throughput two pixels/clock. The asynchronous chroma read is deliberate for this small distributed RAM; BRAM inference is not promised.

Integration is an optional ISP output tap after the final YUY2/TNR stage. Default disabled preserves existing builds. PS AXI port integration, cache synchronization and VCU submission remain necessary before removing encoder_convert on A53. This module uses no full-frame copy.

Design gate: bounded even geometry; explicit non-stallable input and abort contract; single clock; single owner for registers; rounded unsigned 9-bit arithmetic; independent output stability; no multiplier. Acceptance testing covers reference pixels, plane counts and stall abort.


## DDR implementation
See DDR_DESIGN.md. nv12_plane_fifo packs each plane into 128-bit FIFO beats; nv12_ddr_writer emits up to 16-beat bursts and retires results after all B responses. nv12_isp_ddr_sink allocates descriptors only at source SOF and counts no-buffer drops. nv12_buffer_pool provides four slots with consumer release, overlap checks and automatic failed-buffer recycle. Connect its descriptor/result channels to the sink; frame_valid transfers a completed buffer to the VCU consumer, whose release must follow encoder input DQBUF. Pool configuration is a handshake interface, not an AXI-Lite driver. Add AXI IDs/attributes in the platform adapter as required by the PS interconnect.

Tests live outside the synthesis tree in tests/zu4ev/nv12. Run run.ps1 there with Vivado 2025.1 installed. Test results are stored under build/nv12_validation. Full-resolution sink tests compare YUY2 input against independently computed DDR Y/UV bytes (same rounded chroma equation as A53), protect row padding and exercise overflow recovery; this does not execute A53 NEON code.


## Managed platform boundary
nv12_capture_output joins nv12_buffer_pool and nv12_isp_ddr_sink. Supply configuration handshakes for up to four disjoint buffers; a pending buffer is allocated only at a final-ISP SOF. frame_valid/frame_ready delivers buffer base, stride and slot tag after DDR completion. The consumer must issue release_valid/release_tag only after VCU has released its input buffer. irq is level-high while irq_enable and frame_valid are high; failed captures recycle and increment failed_frames, without asserting a success-frame IRQ. cfg_error/release_error are single-clock pulses and must be latched by the future register adapter. Reset is a coordinated ownership cancellation; use ENABLE/STOP/IDLE for normal stream stop.

The wrapper is not yet wired to camera_top or PS BD. Existing final-tap signals are converted/cv/cs/ce at video_clk after the TNR stage. Existing YUY2 capture/DP remains a separate consumer. Do not also enable the old USE_NV12 converter when using this wrapper. AXI-Lite configuration, Linux DMA mappings, IRQ wiring and VCU import remain outstanding.


## AXI-Lite peripheral
nv12_capture_peripheral joins nv12_axi_regs and nv12_capture_output. See REGISTERS.md for the register contract. Both AXI-Lite and video use clk; use an AXI clock converter if PS control uses lite_clk. Successful frame IRQ is level-high until software issues TAKE; RELEASE remains a separate command after VCU input completion. No MMIO base address or Linux IRQ number has been assigned yet. The peripheral still needs platform BD, top-level, device-tree and driver integration, with coordinated stop and VCU release before freeing DMA mappings. The old handshake-only tops remain available for tests.


Safe stop is implemented through CONTROL.ENABLE, COMMAND.STOP and STATUS.IDLE (register ABI v2). See REGISTERS.md. Lower-level sink/output instances now require enable/stop_request inputs and expose idle; historical always-on test instances explicitly tie enable high. The writer exposes quiescent. Peripherals reset disabled. Neither IDLE nor STOP automatically returns VCU-owned buffers or deletes pool configuration.
