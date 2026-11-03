# ZU4EV H.264 UVC board validation — 2026-11-02

## Scope and hardware

MiniZU XCZU4EV, SC130GS 1280x1024/120 Hz, PS USB0 DWC3 SuperSpeed,
DisplayPort monitor. Digilent JTAG 210357A7D00EA and COM13/115200 were
identified. Tests use temporary DDR boot; QSPI has not been erased/programmed.
Only CPU0 is online during performance tests. Installed U-Boot overrides DT
bootargs, so `maxcpus=1` alone does not enforce this. The H.264 startup script
offlines CPU1..3 and checks CPU0-only operation before loading video drivers.

## Board fixes

- Configfs frame-based bBitsPerPixel is RO=0. Configure the default color
  descriptor before creating the format; the backported frame-based type has
  no color-link operation and rejects color writes after its refcount increases.
- Patch 0011 handles a cache-disabled VCU (depth=0/core metadata=0), selecting
  the firmware's resource discovery instead of claiming zero available cores.
  Its private encoder-buffer control is zero and read-only when unavailable.
- Enable rate control, set peak equal to target before selecting CBR, and bound
  CPB size. The firmware channel timed out with the original default CPB/peak.
- Patch 0012 enables cached MMAP for raw NV12 input, with ordinary VB2 QBUF/DQBUF
  synchronization. Encoded output stays coherent because the driver reads and
  edits it before VB2 completion. No cache synchronization is skipped.
- Stop scanning an entire uncached AU after the Annex-B predicate is satisfied.
  Earlier full scans caused throughput loss and UVC errors as bitrate increased.

## Measurements on the corrected runtime

- Windows DirectShow identifies H.264 Constrained Baseline, 1280x1024, 60/120 Hz.
- 120 Hz: 14,400 host-recorded frames over approximately 120 seconds with DP
  active; the active stream had zero USB buffer/ownership/ioctl errors.
  Bridge process CPU was approximately 48% of one A53 at 1.2 GHz.
  A sample counted 11,054 returned frames in 92.155 seconds (119.95 fps).
- The 120 Hz recording was 196,206,588 bytes; target bitrate is 20 Mbps, while
  actual scene bitrate is measured from the recording and is not assumed equal
  to the target. Confirm the exact file size in the artifact manifest.
- H.264 decoded without errors after aligning to the first SPS/PPS/IDR and
  supplying the negotiated 120 Hz timebase. Raw DirectShow capture may begin
  with P frames before the next parameter sets; initial acquisition can take
  up to one GOP (approximately one second). `-copyinkf` is used for stream copy.
- Four alternating 60/120 Hz stop/reopen tests each recorded 240 frames when
  allowing three seconds between opens. Immediate reopen can fail while Windows
  re-enumerates after cancellation. Stream cancellation can return an ERROR
  buffer and reset the compressed session; DP/capture continue.
- Native software suite: 13 executables. Kernel/modules, configfs/DT and package
  regressions are rerun for the final image; exact logs are in the board directory.

## Final image acceptance

The earlier `ramtest-final` boot exposed four online CPUs despite DT maxcpus.
That configuration failed after 2,880 host frames with a USB buffer error.
It is superseded by `ramtest-cpu0`, which enforces the tested single-core setup.
The CPU0 package also failed after 13,320 host frames (about 111 seconds),
so single-core configuration is required for the requested system but is NOT
established as the USB error fix. DP continued and the USB error counter rose.
The user confirms occasional counted frame errors existed with raw YUY2 too,
without visible image defects. H264 currently aborts a session on such an error
because later predictive frames may depend on the missing frame.

An H264-only 8192-byte payload candidate is being tested against the previous
49152-byte isochronous payload. This changes request queue coverage; it does
not suppress or reinterpret error buffers. Transport scheduling is a hypothesis,
not a proven cause. The CPU0 production candidate is not accepted for release.
PotPlayer executable is `D:\Programs\PotPlayer\PotPlayerMini64.exe`.
Desktop automation failed because its native pipe is unavailable; actual
PotPlayer playback remains a separate manual acceptance item until observed.

Artifacts and logs: `build/h264_release/board-20261102/`.
Superseded candidate: `build/h264_release/production-cpu0/`.
Superseded DDR bundle: `build/h264_release/ramtest-cpu0/` (not flashable).

## Resumed validation — 2026-11-03

The four-hour user-requested pause ended and its wakeup automation was paused
to prevent repeated launches. The 8192-byte payload image remained on the board,
CPU0 online, maxpacket=1024 and maxburst=7 confirmed over UART.

The complete `ramtest-payload8k` image delivered 72,000 host frames at 120 fps
in 599.31 seconds. The file is 356,352,476 bytes. DP continued throughout and
the gadget counters remained at zero USB errors (72,035 buffers returned).
After first-SPS alignment, host decoding with input rate 120 reported no errors.
Evidence: `payload8k-120.log`, `payload8k-decode-errors.log`, UART markers
`RESUME_8K_IDENTITY` and `PAYLOAD8K_FINAL`.

The scene bitrate during this overnight test was about 4.75 Mbps, lower than
the earlier daytime scene. This is evidence of this test's result, not proof
that the endpoint change eliminates all controller errors at every scene rate.

For resilience, the bridge now keeps UVC connected after a counted buffer
error, drops subsequent predictive AUs, and resumes at a verified SPS/PPS/IDR.
Already queued AUs can precede that recovery IDR. All flagged keyframes must
contain the complete parameter sets and IDR. Recovery is nominally within a GOP
(about one second), and losses remain counted. The recovery counter records
IDRs queued, not proof of host decode. Ownership/ioctl/disconnect failures retain
the existing teardown path. Focused tests observed the original failures and
the native 13-executable suite passes with the new behavior.

`production-recovery` is the new candidate; `ramtest-recovery` is its DDR test
bundle with an additional, unused-by-default fault fixture. The fixture omits
one encoded AU before USB submission and synthesizes its error completion. It
tests host recovery through the real USB link, not the controller error cause.
Production contains no fault fixture.

## Current delivery and acceptance

- Fresh `ramtest-recovery` boot confirmed CPU0 only and bridge SHA256
  `c410d0c13743ed4aa86667601f08cea59aaf3b919b55e7914f30249ab84e8e9f`.
- Production bridge: 36,000 host frames at 120 fps, 299.11 seconds,
  750,814,040 bytes (about 20.02 Mbps over nominal 300 seconds). USB errors=0,
  invalid capture=0, DP continued. First-SPS-aligned decoding reported no errors.
  Evidence: `recovery-package120.log`, `recovery-package120-decode-errors.log`,
  UART `RECOVERY_PACKAGE_RESULT`.
- The one-frame-loss fixture suppressed coded AU180 (45,439 bytes), returned
  a synthetic failed completion, and the bridge skipped 60 predictive AUs before
  queueing the next validated IDR. The same DirectShow session received 2,400
  frames and ended at the requested count, without I/O failure or re-enumeration.
  Decoding from the recovery IDR reported no errors. Evidence:
  `injected-loss120.log`, `injected-loss-after-idr-decode-errors.log`, UART
  `INJECTED_LOSS_RESULT`. This validates software loss recovery over USB;
  it does not reproduce a real DWC3 transfer fault or establish its cause.
- Restored production executable: negotiated 60 fps, recorded 600 host frames,
  decoded without errors; USB error counters remained zero and DP continued.
  Evidence: `recovery-package60.log`, `recovery-package60-decode-errors.log`,
  UART `FINAL_BOARD_STATE`. Production app is left running, fixture stopped.
- All shared files in the production and RAM initramfs are byte-identical;
  the RAM archive's sole extra file is the unused-by-default fault fixture.
  Bridge hash matches the running board. Evidence: `release-runtime-identity.log`.
- Native 13-executable suite passed; additional failed-IDR-QBUF latch assertion
  passed in `recovery-final-test.log`. Production/RAM SHA256SUMS passed.

Deliver `build/h264_release/production-recovery/QSPI_LINUX.bin`, 29,530,692 bytes.
SHA256 `9536513592bc250bdf7dac907781bbaea9a281950456007c12caa7bb98be19e2`.
BOOT offset=0; FIT offset=0x00c00000; NOR capacity=32 MiB.
QSPI was not programmed, so cold boot from the new flash image is unverified.
Production manifest's `hardware_verified=false` remains conservative; the
separate `board-validation.json` records the narrower actual RAM validation.

PotPlayer playback is the remaining user-facing acceptance item. The provided
executable path is known, but another desktop API attempt failed with the same
native-pipe-unavailable error. Windows DirectShow capture/decode is verified;
actual PotPlayer UI playback has not been observed. In PotPlayer, open UVC Camera
as a capture device and choose H.264 / 1280x1024 / 120 fps (60 fps also supported).
Avoid simultaneous access from another capture application. The one-shot resume
automation is removed after this validation run to prevent repeated wakeups.
