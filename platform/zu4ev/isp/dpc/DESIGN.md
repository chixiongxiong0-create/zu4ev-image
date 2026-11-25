# Confirmed-coordinate Mono DPC

## Frozen behavior / architecture

User requires preserving real single-pixel lights and correcting confirmed defects,
including small clusters. Dynamic outlier suppression cannot distinguish them and
is not used. DPC follows FFC and precedes AE/BLC/LTM. No new clock or ready signal.

A sorted sparse map stores up to 1024 horizontal bad runs, lengths 1..32. Entry:
x[10:0], y[20:11], length-minus-one[25:21], reserved[31:26]=0. Runs cannot cross
a row, overlap, or touch in one row (host merges adjacent defects). A whole bad
row has no donor and is rejected. Both donors are outside the confirmed run;
known defects never become donors. Interior: round((left*(L-j)+right*(j+1))/(L+1)).
Left/right edge runs use the one available good donor. Clusters are repaired row
by row; long/full-width defects require another architecture and are rejected.
All unmapped pixels, even 0/1023 isolated points, must remain bit-exact.

Two inactive/active map banks use distributed RAM deliberately: 2x1024x32 bits
avoid scarce BRAM (existing 114.5/128). CPU ordered upload, sorted/range checking,
readback, declared count and output-SOF atomic apply. CPU cannot modify a pending
bank. Disable does not switch banks. Reset bypasses and invalidates map counts,
not RAM. Upload count may be zero only after explicit begin(count=0).

A 32-pair circular FIFO keeps 16 future pairs, enough for every right donor. It
pops at occupancy>16 or when a complete row is queued. Therefore arbitrary bubbles,
row gaps, immediately adjacent rows/frames and final frame drain require no dummy
pixels or vertical frame flush. Two raw taps (head/right donor); last raw good
pixel and saved left donor have explicit row/run lifecycle. No corrected donor
feedback. First output SOF applies a pending map after every previous-frame token
has left the lookup stage, so inactive uploads cannot corrupt an old frame tail.

Pipeline: FIFO/pop and cached run lookup -> raw donor read and weighted numerator
-> reciprocal multiplication -> registered output. Unsigned numerator<=33775 (16 bits), denominator2..33;
ceil(2^24/denominator) multiplication gives exact rounded integer division over
this bounded domain. One-sided/unmapped paths bypass arithmetic but share metadata.
Sustained 2 pixels/clock; input-to-output latency varies with bubbles/row drain.
Fault priority: reset > packet/global/geometry/overflow fault > regular advance.
Fault flushes FIFO and all pipeline valids, emits a fault marker, and waits for a
clean SOF. RAM is not cleared; invalid counters/pointers prevent stale reads.

Modules: dpc_raw10 owns stream buffering, map/config and interpolation; dpc_probe
owns independent one-frame sparse candidate capture. Shared frontend CSR bridge
retains external platform ports. Probe captures original sensor or post-DPC data,
up to1024 candidate positions per even/odd lane; full-frame done only, overflow or
malformed acquisition never usable. Host intersects repeated captures; no live
brightness automatically changes the repair map. Cold defects need uniform bright
field data or a supplied confirmed coordinate list.

## CSR extension, ISP base 0xa0040000

Full aligned writes; PS ownership/ispctl locks required. Read response one cycle.
3100 ID DPC1;3104 version;3108 WO apply2(disable)/3(enable);310c enable/pending/bank;
3110 WO begin inactive upload(count0..1024);3114 apply_seq;3118 uploaded;
311c active_count;3120 completed frame_seq;3124 last repaired pixels;
3128 fault events;312c width/height;3130 capacity;3134 max run32.
3140 probe config:threshold[9:0],bit16 low comparison,bit17 corrected source;
3144 start1;3148 busy/done/overflow/failed;314c lane0_count;3150 lane1_count;
3154 capture_seq. 8000+4*n inactive run read/write; a000+4*n lane0 candidates;
b000+4*n lane1 candidates. Candidate word uses same x/y packing, upper bits zero.

## Acceptance / implementation plan

1. Independent integer golden tests: all run lengths, both lane parities, boundaries,
   2D clusters, unmapped real point/edges/textures, arbitrary bubbles, back-to-back
   frames, idle final drain, faults/resync/reset and bank isolation.
2. AXI AW/W independence, stalled B/R, illegal/partial uploads, FFC regression,
   probe overflow/malformed batches, host map generation and strict parsing.
3. Full1280x1024 test, full synthesis/route/DRC/bus-skew before bitstream.
4. RAM boot, multi-frame covered-sensor survey if still covered, upload/readback,
   correction counters and NV12/VCU/USB/AE regression. QSPI stays recovery image.
No gen_top owner exists; project SystemVerilog is retained. This design is the
agent's bounded choice implementing the user's confirmed-coordinate requirement.
