# Linux / VCU NV12 path

## Files and build
- hardware/add_nv12.tcl extends the validated VCU BD: A0080000 control, 128-bit memory_xbar S06, PS HP0, IRQ1[0]. All new endpoints use video_clk_in=200MHz; no new AXI CDC is introduced. The existing VCU 100MHz control clock is separate and unchanged.
- tools/build_nv12_project.tcl clones build/h264_vcu_final/project/camera.xpr into a new build/nv12_platform project; SC130_NV12 enables final-ISP tap wiring. Use SC130_NV12_PROJECT_OUT for another destination. Requires the existing validated VCU base. This is a source/project build, not a QSPI deployment.
- linux/build_nv12_runtime.sh builds against the existing 6.12 H264 kernel headers without changing kernel configuration. Default outputs build/nv12_platform/runtime: sc130-nv12.dtb, overlay/opt/sc130/sc130_nv12.ko and overlay/usr/bin/sc130_platform_bridge. It runs native software tests and cross-compiles statically for AArch64. The overlay supplements, not replaces, the existing H264 runtime (VCU firmware, existing drivers, init scripts still required).

## Runtime and ownership
With a matching NV12 bitstream and DT, load sc130_nv12.ko after capture/video reset is released. The driver checks RTL ID/version and disabled IDLE. Four persistent coherent buffers (1280x1024 NV12, stride1280) are allocated under a 32-bit DMA mask and configured in the pool. Open /dev/sc130-nv12 is exclusive. GETBUF exports a DMA-BUF fd, not a physical address. Each importer attachment maps an sg_table using that importer's device. This path has no raw-frame CPU mapping/copy/conversion in userspace.

Run sc130_platform_bridge --usb-format h264 --nv12 /dev/sc130-nv12 (and existing output/soft-connect options as needed). Alternatively set SC130_USE_NV12=1 in /etc/sc130-nv12.conf (sourced after /etc/sc130-platform.conf); startup loads the driver and passes the option. It never silently falls back to CPU conversion if NV12 is requested. Legacy mode is preserved when the option is absent. VCU and the actual deployed UVC path remain H264; this change does not switch codec to H265.

Sequence:
1. Open VCU, negotiate NV12 stride/size; incompatible layouts fail before starting capture.
2. Request VCU INPUT buffers with V4L2_MEMORY_DMABUF; GETBUF exports the four PL destinations.
3. Start PL capture. An IRQ is raised only for frames whose AXI writes and B responses completed. The kernel snapshots metadata, TAKEs the slot and queues it in completion order.
4. SC130_NV12_DQBUF -> VCU VIDIOC_QBUF with the exported fd. No CPU pixel access.
5. VCU INPUT VIDIOC_DQBUF -> SC130_NV12_QBUF, returning the PL slot. A completed compressed AU does not itself release the input slot.
6. On shutdown STOP PL and wait IDLE, STREAMOFF/close VCU, then close capture and exported fds. Queue failure uses the same cancellation barrier; it does not optimistically release potentially referenced input memory.

The hardware completion FIFO and driver sequence ordering preserve temporal order across slot wrap under backpressure. The driver timestamps completion/IRQ collection with CLOCK_MONOTONIC; it does not provide source SOF timestamps. At 120fps every delivered frame is submitted; 60fps applies a completion-time cadence filter before VCU ownership. Source and output frame timing and actual CPU savings require board measurement. Encoded AU copying into USB buffers remains, as before; only raw conversion/copy is removed.

## Stop and lifetime limits
SC130_NV12_STOP waits up to one second for PL IDLE. Timeout poisons the capture session and retains allocations; it never frees memory still reachable by PL. IDLE does not imply VCU input completion. The supplied bridge enforces the close order above. Other clients must return slots only after their consumers finish. The module deliberately retains buffer allocations/configuration across open/close; exported buffers retain device/module references. Reset/rebind and replacement of configured memory require a matching stopped/reset platform and coordinated consumer cancellation, not unbinding a live device. External reset while streaming is unsupported.

## Interrupt and address evidence
PL IRQ1[0] is GIC INTID136, so DT uses <0 104 4> (SPI numbering subtracts32). Verified against AMD PG201 Programmable Logic Clocks and Interrupts, and compiled DT fdtget returned `0 68 4` (hex). NV12 control reg tuple returned `0 a0080000 0 10000`. AMD reference: https://docs.amd.com/r/en-US/pg201-zynq-ultrascale-plus-processing-system/Programmable-Logic-Clocks-and-Interrupts

## Verification scope
Native regression includes mocked VCU/DMA-BUF ownership, no raw mmap, delayed input DQBUF, queue failure and close cancellation. RTL regression includes frame order, buffer hold/release, DDR byte comparison, errors and stop drain. Linux module and AArch64 executable compile against the existing kernel. None of these substitutes for a real VCU import run or a board CPU measurement. Do not pair the NV12 DT/module with an old bitstream lacking A0080000.


## Board validation update - 2026-11-05
Real VCU DMABUF import, PL capture, H264 encoding and host USB decode have passed in a temporary RAM boot. See [BOARD_TEST.md](BOARD_TEST.md) for measurements, evidence paths and remaining limits. The earlier verification-scope paragraph describes pre-board validation.
