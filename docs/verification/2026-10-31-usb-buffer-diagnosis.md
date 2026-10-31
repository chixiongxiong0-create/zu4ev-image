# USB buffer error diagnosis, 2026-10-31

The sustained USB test returned real error-marked output buffers. It was not an
error-free run, and normal STREAMOFF cancellation does not explain the observed
errors. No implementation or error-counter change was made during this diagnosis.

## Confirmed board observations

- Target: Linux `6.12.0 #8 SMP Thu Oct 22 07:39:05 CST 2026 aarch64`.
  Gadget `uvc.usb1`: maxpacket 3072, maxburst 15, interval 1.
- FFmpeg DirectShow, YUY2 1280x1024 at 120 fps, ten seconds: exit 0, 1199 frames.
  Successful host completion does not establish image integrity.
- Kernel log reported streaming alternate setting 1 at uptime 1429.687 s and
  alternate setting 0 at 1440.005 s. Bridge error timestamps were
  1432.404383173, 1432.659875183 and 1432.802495099 s: all inside that interval.
- Each of these three dequeued output buffers had flags `0x4040`, bytesused 0,
  sequence 0, and bridge `streaming=1 on=1`. The flags combine
  `V4L2_BUF_FLAG_TIMESTAMP_COPY` (0x4000) with `V4L2_BUF_FLAG_ERROR` (0x40).
  The former describes timestamp handling; the latter is the actual error.
- Over the first sustained interval, sent/returned advanced 113/112 to
  1193/1192. Buffer errors advanced 0 to 3; ownership, DQBUF, event and send
  errors stayed zero. Capture invalid stayed zero, capture drop stayed at its
  pre-existing cumulative value 9, and capture/DP continued near 120 fps.
- A later alternate-setting-1 event at 1619.248 s came from an unidentified
  host client. Sampled buffer errors subsequently reached 32; this was not a
  second controlled FFmpeg test. The unknown client was left undisturbed.
- The recent kernel-log excerpt had no `VS request missed xfer` message.
  Debugfs was not mounted and dynamic-debug control was unavailable; diagnostic
  logging was not enabled or otherwise changed.

The bounded source log excerpt is
`build/ibex_small/board_reports/20261031_ae_usb/usb_target_excerpt.txt`;
the main board report is `BOARD_TEST.md` in the same directory.

## Linux 6.12 source inference

In upstream Linux v6.12, `uvcg_complete_buffer()` clears payload to zero and
returns an ERROR buffer when `UVC_QUEUE_DROP_INCOMPLETE` is set. The normal
completion path instead publishes the frame payload and increments the sequence.
This closely matches the zero-payload/sequence-zero observations.
[Source: uvc_queue.c](https://github.com/torvalds/linux/blob/v6.12/drivers/usb/gadget/function/uvc_queue.c#L306-L321).

The corresponding `uvc_video_complete()` path sets DROP_INCOMPLETE when a
nonempty USB request completes with `-EXDEV`, described by its debug message as
a missed transfer. Shutdown and other completion errors take cancellation paths.
Thus a missed isochronous transfer is the strongest current explanation for the
observed signature. This is an inference from upstream source, not a captured
request status from the deployed board kernel.
[Source: uvc_video.c](https://github.com/torvalds/linux/blob/v6.12/drivers/usb/gadget/function/uvc_video.c#L374-L398).

## Application ownership review

The reviewed implementation is the frozen v3 bundle's
`software/platform_bridge.c`, `capture_broker.h` and `uvc_core.c`.
The shared path holds the capture source before output QBUF, releases it after
output DQBUF, and permits capture reuse only after USB and DP holds are released.
STREAMOFF/close forms the cancellation barrier before source release. No specific
lifetime violation was identified in this bounded review. Zero ownership-error
counters are supporting evidence, not proof that every DMA interaction is correct.

The logged slot `state=0` is expected: `usb_complete()` calls
`policy_usb_done()` before reporting the error, so the diagnostic prints the
post-completion FREE state. It does not demonstrate premature source reuse.
An ERROR DQBUF still returns ownership; the application correctly retains the
error count while releasing that completed source.

## Remaining uncertainty and scope

The deployed kernel's exact source/patch identity and a correlated USB request
status were not obtained. The observations do not establish whether the missed
transfer originates in controller scheduling, kernel request handling, host/link
conditions, or another cause. They also do not establish that this behavior
predates the Ibex integration; no matching controlled pre-change baseline exists.

For a separate USB investigation, correlate the deployed kernel's UVC request
completion status with a bounded controlled stream before selecting a fix. A
targeted dynamic-debug/trace capture can test the EXDEV inference when the host
client is controlled. Kernel or USB architecture changes are outside this board
test. Buffer errors remain an unresolved validation risk; they must not be
filtered, renamed as successful frames, or removed from the total.

Verification for this diagnosis: bounded source review, timestamp comparison and
read-only board log/configuration observations. No RTL, bridge implementation,
kernel, gadget configuration, frozen v3 bundle or original ZU4EV source was edited;
no rebuild or new hardware test was needed for this documentation-only result.
