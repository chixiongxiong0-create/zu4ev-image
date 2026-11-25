# ZU4EV H.264 UVC output

The user requests VCU hardware H.264 compression before USB, using the final
Ibex ISP-master/shared DMA-BUF platform, with DP remaining functional.
Continue instruction authorizes implementation without another design gate.

## Existing architecture and selected approach

The published platform uses PS USB0/DWC3 with Linux configfs f_uvc; the external
USB chip described earlier must not be assumed to be a programmable controller.
Capture produces 1280x1024 YUY2 at 120 fps. DP and USB currently import the same
capture DMA-BUFs. Source ownership lives in capture_broker.h.

Retain the original YUY2 capture and DP import. Add a separate encoder reader
and independent compressed output buffers. Never overwrite a shared capture
buffer to convert its format. If the VCU input is NV12, use a separate conversion
buffer, with explicit DMA completion/cache synchronization. The implementation
uses a read-only AArch64 NEON conversion into encoder-owned NV12 storage because
the available upstream driver cannot import packed YUY2. Its CPU cost and 120 fps
throughput remain board acceptance items; hardware H.264 encoding is mandatory.

USB must advertise actual H.264 frame-based descriptors and negotiate variable
frame sizes. Compressed bytes must be Annex B access units, with SPS/PPS and an
IDR after each new host stream. Send each encoded access unit exactly once in
order. Do not use the raw-video latest-frame dropping policy after encoding:
dropping reference frames corrupts the decoded stream. Bound queues; on overflow
restart prediction at an IDR rather than silently discarding arbitrary frames.

Other approaches considered: change the raw buffer in place (rejected: corrupts
DP); keep YUY2 descriptors while sending H.264 (rejected: invalid UVC); software
H.264 on the A53 (rejected: user requests VCU and throughput is not established).

## Ownership and lifecycle

A raw capture buffer may be requeued only when latest retention, DP, raw USB
(legacy diagnostics), and encoder readers have all released it. VCU input release
is separate from encoded-output completion. Encoded buffers remain immutable
until UVC completion. USB stop/disconnect cancels USB/encoder work before releasing
DMA-owned storage, and must not stop capture/DP. Failed cancellation quarantines
storage; it does not make it reusable. No B frames by default; bounded GOP and
repeated headers allow low-latency recovery. Preserve 120/60 fps negotiation.

## Integration and acceptance

Add real VCU hardware/DT/kernel/firmware integration, not merely a format label.
Check installed AMD 2025.1 components before selecting the encoder API. Current
kernel sources lack frame-based gadget support; backport a tested implementation
or explicitly reject unsupported kernels. Keep a legacy YUY2 option for recovery.

The user subsequently authorizes RAM board validation and QSPI artifact generation.
QSPI flash replacement is not part of this request. Missing JTAG connectivity must
be recorded as an unpassed hardware acceptance gate, never inferred from builds.

Focused offline tests cover reader ownership, stop failures, UVC descriptor and
probe consistency, variable bytesused, access-unit ordering, IDR restart, and
preservation of existing DP tests. Build AArch64 software and applicable kernel
components. Hardware acceptance requires a matching bitstream, successful VCU
encode at 1280x1024@120, independent DP with USB closed/reopened, Windows/PotPlayer
UVC capture and measured CPU/frame/error counters. Do not flash automatically.
