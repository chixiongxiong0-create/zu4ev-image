# ISP configuration path and micro-architecture

The isolated board copy connects Ibex to the real `isp_axi_regs` through a
native bundled-data clock crossing, an AXI-Lite master, and an ownership gate.
The original ZU4EV tree is never modified. Snapshot and peripheral windows are
unchanged. Ibex registers occupy `0x51000000..0x5100ffff`, translating to the
existing 16-bit ISP offsets. PS retains its `0xA0040000` base, established in
the platform's `tools/prepare_isp_control.tcl`.

## Ownership contract

Offset `0xff00` is reserved by the gate (PS `0xA004ff00`, Ibex `0x5100ff00`).
Read bit 0 is the current owner: 0 PS (reset default), 1 Ibex. PS alone can
write bit 0 with byte strobe 0 enabled; other enabled data bits must be zero.
Ibex writes return SLVERR. PS can always reclaim ownership through this CSR.
All other accesses from a nonowner return SLVERR and never reach the ISP.
No existing `go` bit or FE acknowledge signal changes meaning.

PS software must first stop its complete ISP configuration sequence, including
pending frame-boundary commit, then grant and read back 1. Ibex must finish its
sequence and notify PS by the application's chosen communication before PS
reclaims and reads back 0. The gate enforces transaction boundaries; firmware
must coordinate sequences and frame-boundary completion. PS must not forcibly
reclaim while Ibex is still changing its shadow registers.

## Frozen cycle and state contract

* The native crossing accepts exactly one request with `req && gnt`, holds
  address/data/strobes until the return acknowledgement, and returns one pulse.
  Two-stage toggle synchronizers precede each payload capture. Request and
  response payloads stay stable while their toggles cross. Both domains must
  reset together to abandon traffic; stopping the ISP clock stalls completion.
* The AXI master owns independent AW and W valid bits, held until each handshake;
  a write completes at B and a read at R. Native error is AXI response != OKAY.
* The gate owns per-client one-entry AW, W and AR buffers and response registers.
  One global downstream FSM selects a complete buffered write or buffered read
  only in IDLE. Priority is PS write, PS read, CPU write, CPU read. This favors
  PS recovery. A denied request or CSR access completes locally. Forwarded
  requests pass SEND_WRITE -> WAIT_B -> IDLE or SEND_READ -> WAIT_R -> IDLE.
  The selected client/address remain held through response consumption.
* Ownership updates only in IDLE on a completed buffered PS CSR write. All
  earlier downstream requests have finished; accepted partial AW/W pairs remain
  buffered and are classified under ownership when selected. Software must not
  pipeline transactions across the handoff. Responses remain stable under
  client backpressure. WSTRB is preserved.
* Shared video reset resets ISP and ownership; resetting just the CPU does not
  revoke ownership. The native crossing uses system reset, so accepted transfers
  drain even if the CPU resets; the core may discard that response.

## Module and verification boundaries

`ibex_isp_cfg_cdc` owns CDC storage, toggles, busy lifecycle and response pulse.
`ibex_native_to_axi_lite` owns native/AXI sequencing, without clock crossings.
`ibex_isp_cfg_owner` owns PS/CPU channel buffers, transaction sequencing and owner.
These boundaries allow independent backpressure, reset and denial tests. A
single combined controller would mix unrelated CDC and AXI ownership lifecycles.
No arithmetic or algorithm pipeline is needed. Existing SystemVerilog sources
are hand-authored; this project does not require gen_top.

Focused verification must connect the gate to the actual platform register
module, exercise both AW/W orders, response backpressure, owner transitions,
nonowner errors, WSTRB, reset, and a CPU firmware write/read sequence. Routed CDC
constraints bound the held payload paths separately from the toggle synchronizers.
Board synthesis, timing and hardware operation require separate validation.

## Board reset wiring

The debug block exports `cfg_reset_no`, asynchronously asserted from
`axi_resetn & uvc_resetn` and released through two video-clock stages. This resets
both mailbox domains, the AXI master, the owner gate, and only the copied
`isp_axi_regs` instance. The video pipeline retains its original `uvc_resetn`.
The register path stays reset during the debug startup counter (256 lite clock
cycles), so PS traffic waits briefly before configuration becomes available.
VIO reset uses `EnableCpuResetInput` and `cpu_rst_ni` to reset only the core and
CPU routing state. It does not flush accepted bus operations: an accepted write
can finish after CPU reset; reset does not roll back shadow or active settings.
Global reset must be asserted to both sides when abandoning a transfer. An
independently asserted register reset cannot safely retain partial AXI traffic.
