# H.264 UVC verification record — 2026-11-02

The later board session and its corrected release are documented in
[BOARD_VALIDATION_20261102.md](BOARD_VALIDATION_20261102.md). The offline
artifact hashes and hardware-unavailable notes below describe the earlier
candidate, which has been superseded by that board session.

## Implemented behavior

USB defaults to hardware VCU H.264 with frame-based UVC descriptors. DP keeps
YUY2 capture DMA-BUFs. Source reads, private NV12 conversion storage, encoded
access units, and USB output buffers have separate lifetimes. Only unencoded
source frames may be skipped; encoded reference frames are sent in order.
Each new encoder session requires Annex B SPS/PPS/IDR. Failed USB buffer
completion terminates the compressed session rather than continuing with a
broken prediction chain. USB shutdown does not stop DP/capture.

## Verified offline

- Native software suite: 13 test executables passed, including existing DP/raw
  USB tests, encoder ownership, actual variable-size UVC queue submission,
  backpressure/order, failed STREAMOFF cancellation, and 120 fps cadence jitter.
- AArch64 static applications compiled; NEON conversion tested under QEMU
  against a per-pixel reference with guard bytes and unchanged YUY2 source.
- UVC frame-based kernel patches compile on the matching Xilinx Linux 6.12.
- New kernel Image, Allegro/VCU clock modules, and capture modules built.
- Device tree compilation clean. VCU control base A1000000, interrupt SPI96.
- Official AMD firmware pinned to revision
  `29ab982965b797b1c9b567faba47378578398f4a`, verified byte sizes and SHA256;
  firmware license included in runtime overlay.
- QSPI packaging tests: eight tests passed. Runtime overlay preserves Ibex
  coordinator and device-node records; FIT payloads are extracted and compared.

Frozen bridge SHA256:
`47c56e14b106017fbe30c7fa6588c7f71d1d17853ff8c77e2e1082490c2e81c9`.
Build location: `/home/developer/zu4ev/sc130-h264-build/software/` in WSL.
Kernel, DTB and minimal runtime overlay use the same `sc130-h264-build` root.

## Hardware acceptance remains open

The user confirmed on 2026-11-02 that the hardware environment is currently
unavailable. This run therefore completes offline artifacts only; board tests
are intentionally deferred rather than treated as passed.

Ross Vivado MCP discovery on localhost:3121 returned no hardware targets,
including after refresh. Windows COM10 was present but could not be opened
(`Access denied`); no other application's serial connection was taken over.
No RAM boot, VCU firmware initialization, actual encoded capture, DP coexistence,
Windows/PotPlayer decoding, latency or sustained 120 fps measurement has passed.
QSPI has not been erased or programmed.

The A53 converts YUY2 to NV12 using NEON. CPU usage and achieved frame rate must
be measured on the single-core Linux configuration. VCU performs compression.
The 2019.2 firmware is supported by the selected upstream driver; actual
initialization with the generated VCU 1.2 hardware remains a board test.

## FPGA and release artifacts

Final offline build and packaging completed on 2026-11-02. FPGA build is in
`build/h264_vcu_final`; accepted release artifacts are in `build/h264_release`.
The final build uses a 100 MHz VCU AXI-lite control clock, 200 MHz encoder/memory
interfaces, and 33,333,333 Hz reference. The earlier 200 MHz control build failed
minimum-period checks and is not a release input. Serial synthesis was used after
memory exhaustion and a parallel synthesis stall.

Final routed timing: WNS 0.117 ns, TNS 0; WHS 0.010 ns, THS 0;
WPWS 0.143 ns, TPWS 0. Timing, DRC error and bus-skew gates passed. No missing
clocks or unconstrained internal endpoints. Existing 4 input/3 output missing-delay
interface checks and DSP/RAMB advisory warnings remain; this is not a zero-warning
build. Reports are copied into `build/h264_release/*_acceptance.rpt`.

Accepted bitstream SHA256:
`365b4626ef74ffe746d4b248ed946350335571374fa6524503e9b704c91ca5e2`.
Corrected DTB SHA256:
`f8e791c02eee654e9c3a7a7b587e4c0d43ac40837dd7f3bf7c0013703d04d56d`.

Production `build/h264_release/production/QSPI_LINUX.bin` is 29,641,264 bytes,
with BOOT at zero and FIT at 0x00c00000, within the existing 32 MiB layout.
SHA256: `937d5afaa22675d596d802912aa4818146437f49d9bf74ad2aee18d7a3f0ea80`.
Its full SHA256SUMS, FIT extraction checks, erased gap and runtime contents passed.
The packaged bridge hash matches the frozen binary above; VCU firmware/modules,
H.264 setup and Ibex coordinator were verified inside the generated initramfs.

`build/h264_release/ramtest` is a temporary DDR boot bundle, marked
`flashable=false`, and contains no `QSPI_LINUX.bin`. Both variants explicitly
record `hardware_verified=false`. No physical boot or flash write was performed.
