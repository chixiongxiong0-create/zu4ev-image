# NV12 hardware board test — 2026-11-05

RAM-only boot on the connected ZU4EV board. QSPI was not erased or programmed.
The board remains on the NV12 candidate until reset/power cycle. No RTL was
changed during this board test. The deployed codec remains H.264.

## Accepted implementation

Vivado 2025.1 completed `impl_1` and generated `camera_top.bit` on November 4.
Routed setup WNS +0.033 ns, hold WHS +0.010 ns, TNS/THS zero. Timing, DRC
(zero errors), and bus-skew acceptance hook passed before bitstream generation.
Reports: `build/nv12_platform/route_reports/`.

The temporary BOOT.BIN uses the validated RAM FSBL, PMUFW, BL31 and U-Boot;
only the PL image changes. The FIT retains the baseline Linux kernel and VCU
firmware/modules and appends the NV12 runtime overlay. New configuration is
`/etc/sc130-nv12.conf`. Startup loads the NV12 driver and runs the bridge with
`--nv12 /dev/sc130-nv12`; CPU conversion is not used on this path.

## Observed results

- `/dev/sc130-nv12` appeared. VCU negotiated NV12 1280x1024, stride 1280,
  sizeimage 1966080 and four V4L2 DMABUF slots.
- Real capture/VCU probe: 120 frames / 1017.846 ms; 2400 frames / 20182.185 ms
  (about 118.9 fps), both returned success. Repeated open/STOP/close worked.
- Five captured H.264 frames were transferred over UART and decoded on the
  host; all were 1280x1024 yuv420p. The image showed the current camera scene.
- Host DirectShow opened `UVC Camera` at 1280x1024 / 120 fps. First capture
  received 26019578 bytes in 35.298 seconds including open/close overhead;
  offline decode produced 4022 frames. This is not a claim of zero startup
  frame loss. The steady-state board log advanced 1775 to 2975 encoded frames
  over ten seconds, with all USB error counters zero and DP flips increasing.
- At CPU0 1199999 kHz, the same ten-second window had CPU0 jiffy delta
  `[15,0,303,662,0,0,0,0,0,0]`: busy 32.449%, idle 67.551%.
  The earlier CPU-conversion streaming baseline was busy 75.287%, idle 24.713%.
  Preliminary saving is **42.84 percentage points of one A53 core**, or 56.9%
  less measured CPU work. Scene/compressed bitrate and test time differ;
  this is not a controlled same-scene A/B benchmark or a four-core saving.

- A second host USB session decoded 4015 frames. Its ten-second steady-state
  CPU0 window measured busy 34.327%, idle 65.673%. NV12 no-buffer and failed
  counters stayed at 19 and 4 throughout this interval, respectively. Across
  both USB samples, preliminary saving is about 41-43 points of one A53 core.
- The user reopened PotPlayer. It submitted STREAMON and about 910 frames were
  encoded before host STREAMOFF at 7.7 seconds. The user confirmed manually
  stopping playback. One USB error buffer appeared during that stop; it is
  not evidence of spontaneous stream failure. No GUI image-quality claim is made.

The failure counter includes intentionally aborted in-progress frames on STOP;
it must be assessed over a streaming interval, not assumed to mean AXI BRESP
errors. PL IDLE after close was observed (STATUS=6, CONTROL=0).

## Evidence and remaining scope

`build/nv12_platform/board_20261105/` contains `ram_boot.log`, `uart.log`,
`measurements.json`, the host capture script/logs, compressed streams and
decoded PNGs. `build/nv12_platform/ram_candidate/` contains the temporary
BOOT.BIN, FIT, BIF and manifest. These are RAM-test artifacts, not a flash release.

PotPlayer was reopened and then manually stopped by the user. Host USB
receive/decode was verified independently. DP activity
is proven by flip counters; physical monitor quality was not visually inspected.
Long-duration soak, controlled CPU A/B, and real color/chroma comparison against
the A53 converter remain outside this short board test.
