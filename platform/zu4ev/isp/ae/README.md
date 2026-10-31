# RAW10 frame statistics

`ae_stats_raw10.sv` passively observes two RAW10 pixels per valid beat (low
10 bits first). Supported frame dimensions are even WIDTH >= 2 and HEIGHT >= 2.
There is no ready signal: every asserted `s_valid` is a transfer, including SOF
and EOL. SOF/EOL are meaningful on valid beats; packet/global faults are also
honored between beats. Configuration is sampled on valid SOF. Input frame
numbers start at 1, advance at every valid SOF and wrap modulo 2^32.

The default is enabled, full frame, black level 52. Region encodings 0..3 select
centered area fractions 1/4, 1/2, 3/4, full. Width and height are even integer
floors of the exact square-root scale, minimum 2. Boundaries are evaluated per
pixel, including odd ROI origins. Each pixel contributes max(raw-black,0).

Accumulation uses 48 bits and count uses 32 bits. At the final expected EOL,
a well-formed frame transfers its sum/count and metadata to a 48-cycle binary
restoring divider. It publishes floor(sum/count), sum, count, frame, ROI and
configuration atomically, incrementing sequence. A completion while the divider
is busy is dropped and increments overrun (including the divider's final cycle).
A new SOF can accumulate independently. Old results remain valid while disabled.

Malformed EOL/line length, packet/global faults, or an early SOF invalidate the
frame. An invalid frame increments bad_frames once; an early SOF also counts
its abandoned predecessor if not already counted. Disabled frames are still
tracked for protocol errors. After the expected final row, any additional valid
beat without SOF, or packet/global fault before the next SOF, invalidates that
completed frame and increments bad_frames once. If its division is pending,
it is canceled (even on the final divider cycle), preserving the previous
valid result. If it has already published, result_valid is cleared while the
published fields and sequence remain unchanged. A new SOF assigns subsequent
faults to the new frame and cannot cancel the preceding frame's computation.
Late errors cannot retract data already consumed by software. Missing SOF
means no new frame. A missing last EOL
is detected at that beat. A truncated frame is detected at the next SOF;
there is no timeout on an indefinitely stalled stream.

## Runtime register map

Available only with `USE_LTM && RUNTIME_CONFIG`; legacy builds have no added
source dependency in their elaborated hierarchy. `isp_axi_regs` parameter
`AE_STATS` defaults to 0 for standalone legacy instances; frontend sets it to 1.
Capability register 0x008 bit4 advertises the block. Check it before accessing
0x200: unmapped reads can produce an AXI error on old firmware.

All offsets are relative to ISP base (default 0xA0040000), aligned 32-bit words.
Writes to read-only/undefined words or reserved set bits return SLVERR. Control
and black writes honor byte strobes and validate the merged value. Statistics
configuration is independent of ISP apply/pending and latches at the next SOF.
Separate writes can straddle SOF; returned result configuration identifies what
was actually used.

| Offset | Field |
|---|---|
| 0x200 | ID 0x41455331 (`AES1`), RO |
| 0x204 | version 0x00010000, RO |
| 0x208 | enable bit0; region bits2:1; default 7, RW |
| 0x20c | black bits9:0; default 52, RW |
| 0x210 | valid bit0, divider busy bit1, SOF-latched enable bit2, RO |
| 0x214 | publication sequence, RO |
| 0x218 | published input frame number, RO |
| 0x21c | integer mean, RO |
| 0x220 | actual pixel count, RO |
| 0x224 / 0x228 | sum low32 / high16 (upper16 zero), RO |
| 0x22c | bad frame count, RO |
| 0x230 | overrun count, RO |
| 0x234 | published region bits1:0, black bits17:8, RO |
| 0x238 / 0x23c | published ROI x / y origin, RO |
| 0x240 / 0x244 | published ROI width / height, RO |

All counters wrap modulo 2^32 and reset only on resetn. Reset invalidates the
result and clears published data. Read sequence, valid and result fields, then
sequence and validity again; retry if sequence differs, and reject the snapshot
if either validity observation is false. This also catches late invalidation
without a sequence increment. Live status/error counters are not
part of the published frame snapshot. `ispctl stats read` bounds retries at 16.

This module provides measurements only; it does not alter sensor exposure.
The SC130GS guide describes exposure/gain written in N taking effect in N+2;
actual timing requires a common sensor-write/SOF time reference on hardware.
