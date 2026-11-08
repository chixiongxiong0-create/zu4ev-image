# Mono RAW10 FFC

## Frozen behavior and micro-architecture

Two pixels/clock, video clock and reset; no ready on the CSI broadcast input.
FFC precedes both raw AE statistics and BLC/LTM. Existing ingress continues to
own stream geometry/fault recovery. FFC delays pixels and all fault qualifiers
by six registered stages, including bypass. Position restarts on each valid SOF.
Invalid cycles do not advance position. Maximum supported geometry is 1280x1024,
even width; production grid spacing is 32 pixels, nodes 41x33. No gen_top owner
exists for this SystemVerilog project.

`out = clip10(round(max(raw - dark(x,y),0) * gainQ12(x,y)/4096) + pedestal)`.
Dark and gain use bilinear interpolation of unsigned 10/14-bit nodes, rounded
half-up once after the two interpolation axes (weight denominator 1024).
Pedestal defaults to 52 to preserve existing BLC; gain range 1..16383 (<4x).
Dark-only calibration installs unity gain. It is not a measured bright-field map.

Bounded choice: coarse smooth-field FFC, not per-pixel DSNU/PRNU correction or
bad-pixel replacement. Cell statistics alone cannot identify individual hot pixels.
Four identical coefficient RAM copies allow simultaneous four-corner reads;
each has a synchronous video port and CPU port, replicated CPU writes. Two banks
permit inactive upload with no active-frame changes. Reset invalidates tables,
does not clear BRAM; bypass never consumes uninitialized coefficients.

RAM leaf `ffc_dual_ram` uses one synchronous read-first read/write port and one
synchronous read port, with no storage reset. AXI read acceptance is serialized
against a buffered write to avoid sharing the coefficient CPU port in one cycle.
The statistics accumulator shares its read/write address; segment-start reads
are consumed at segment-end, at least 15 pixel-pair clocks later.

Modules: `ffc_raw10` owns coefficient banks, frame configuration, pipeline and
raw stream coordinates; `ffc_stats` owns acquisition and frozen cell sums.
Separate statistics module makes malformed-frame rejection independently testable.
AXI transport remains in existing `isp_axi_regs`; new CSR request/data ports
are same-clock pulses with one-cycle synchronous read response.

Events: valid SOF applies pending bank/enable/pedestal atomically, including its
first pair. Upload is ordered node0..last; partial/duplicate/out-of-order writes
are rejected. Apply with enable requires a complete inactive table. Pending
locks all configuration writes until SOF. Disable may apply without a table.
Reset cancels pending and acquisition; no partial calibration is published.

Pipeline: corner reads + raw/meta -> vertical weighted sums -> horizontal sums
and rounded node values -> nonnegative subtraction -> multiply -> round, pedestal,
saturation and output. Throughput 1 pair/clock, latency 6 registered stages.
Metadata/bypass enable/pedestal travel with each pair. No new clock domain.

Statistics acquisition: clear 1280 cell accumulators, wait SOF, capture exactly
32 complete frames; per-32-pixel row segment sum is added once to its cell.
Each cell then represents 32*32*32 samples (32768); 32-bit sums are sufficient.
Any malformed row, unexpected SOF, packet/global fault fails the entire batch;
host must restart. The frozen result is readable only after done, never during
capture. No DMA buffers and no A53 per-pixel processing are required.

## Register extension (ISP base 0xa0040000)

Owner handoff applies: stop Ibex before any CPU access; restore only after all
CPU writes complete. All extension writes require full strobes/alignment.

| Offset | Access | Meaning |
|---|---|---|
| 3000 | RO | FFC1 ID 0x46464331 |
| 3004 | RO | version 0x00010000 |
| 3008 | WO | apply: bit0 enable, bit1 apply (must be1) |
| 300c | RO | bit0 active enable, bit1 pending, bit2 active bank |
| 3010 | RW | shadow pedestal 0..1023, default52 |
| 3014 | RO | completed apply sequence |
| 3018 | RO | inactive ordered upload count |
| 301c | RO | nodes (rows<<16)|columns |
| 3020 | RO | image (height<<16)|width |
| 3024 | RO | grid spacing |
| 3040 | WO | start statistics:1 |
| 3044 | RO | statistics bit0 busy, bit1 done, bit2 failed |
| 3048 | RO | complete frames in batch |
| 304c | RO | samples per cell in completed batch |
| 3050 | RW | statistics source:0 original RAW,1 corrected RAW; only when idle |
| 4000+4*n | RW | inactive node: bits23:10 gainQ12, bits9:0 dark |
| 6000+4*n | RO | frozen raw cell sums, row-major |

Validation gates: exact identity/bypass, bilinear ramps, saturation, bank atomicity,
independent AXI channels/backpressure, ordered uploads, malformed batch failure,
random input bubbles, full geometry statistics, integration regressions,
full synthesis/route timing/DRC, RAM board capture and runtime before persistence.
Existing validated QSPI and its full backup remain recovery artifacts.
