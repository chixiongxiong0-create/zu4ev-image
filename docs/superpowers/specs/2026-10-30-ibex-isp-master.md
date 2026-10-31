# Ibex ISP master and shared USB source bundle

Architecture frozen 2026-10-30. The original ZU4EV tree remains unchanged.
The target is a fresh source copy, native AE firmware and an offline bitstream;
physical closed-loop, I2C electrical timing and USB throughput remain board tests.

## Ownership and lifecycle

PS boots the existing camera, sensor and ISP configuration. R5 AE and every PS
IIC/ISP writer must be stopped before handoff. USB/DP capture consumers continue.
The owner gate retains ff00 (PS bit0, reset 0), adds ff04 status and ff08 RUN
(PS bit0, reset 0). Only PS can write ff00/ff08. RUN1 requires owner1. Owner0
requires RUN0 and synchronized quiescent1. All control writes preserve WSTRB
and reject other enabled data bits. Read-only status writes return SLVERR.

ff04 bits: quiescent0, sensor grant1, I2C busy2, armed3, fault4,
restart-required5, firmware boot-ready6, sampled SCL7/SDA8, stop-ack9. All are independent
status flags, synchronized through two video-clock stages; software waits for
stable predicates, not a multi-bit atomic counter. Quiescent is one source
registered predicate requiring firmware quiescence AND NOT busy/start. Firmware marks it only after ending its
entire sensor/configuration sequence, with an ordering fence. Gate selection
of the PS status request follows completion of earlier downstream AXI traffic.

PS handoff: confirm ISP commit idle and exclusive stopped IIC0/R5; wait
boot-ready and quiescent; owner1; wait sensor-grant; RUN1. RUN is the video-ready
authorization, so no JTAG RAM authorization is necessary. Stop: RUN0; firmware
finishes current exposure/gain and verification, acknowledges quiescence;
PS waits quiescent and this stop request's matching acknowledgement, writes
owner0, and waits sensor-grant0 before driving IIC. An accepted RUN0 write while
no stop is pending toggles stop-request (ff08 read bit1); pending RUN0 writes
are idempotent and do not toggle again. RUN1 is rejected while stop is pending.
The lite side returns stop-ack only after RUN0, disarm and drained quiescence.
The gate requires the matching stop-ack before owner0, preventing old-q and
toggle-ABA races. Arming clears source quiescence in the same cycle.
A fault publishes fault and quiescence after the accepted I2C finishes. A dead
firmware remains nonquiescent; the tool times out instead of stealing the bus.

CPU-only reset does not reset the I2C engine or mux. An accepted transaction
finishes through STOP (or the bounded timeout releases both lines). It clears
armed/boot-ready, raises restart-required and forbids further commands. Firmware
restarts from fresh initialized RAM globals. PS must explicitly lower RUN then
raise it after boot-ready/grant to restart; a stale RUN1 cannot restart AE.
Quiescence cannot be observed until the accepted transaction has retired. A
reset in a two-register exposure update can leave a partial sensor exposure;
the restart rereads both bytes rather than claiming the prior proposal applied.

## Hardware boundaries

| Module | Responsibility/state owner | Clock/reset | Focused target |
|---|---|---|---|
| ibex_sensor_i2c | one 16-bit-register, one-byte transaction; byte/bit/phase counters, shift register, completion/errors | lite/global reset | wire-level slave, NACK/stretch/timeout |
| ibex_sensor_ctrl | native CSR, timer, arm/firmware state, command snapshot and safe mux grant | lite/global reset, CPU reset inhibits commands | CSR/ownership/reset lifecycle |
| ibex_isp_cfg_owner | existing AXI buffers/transaction owner plus PS RUN/status | video/coordinated reset | existing AXI tests plus RUN/quiescent guard |
| isolated soc_subsystem | single IOBUF per pin; select PS release versus Ibex pull-low | grant already lite registered | mux elaboration, open-drain checks |

A combined AXI/CDC/I2C module was rejected: protocol ownership and transaction
state have independent resets and test contracts. Importing the entire OpenTitan
TL-UL peripheral system was rejected for this bounded sensor interface because
the validated board does not instantiate it and its dependency/resource cost is
unnecessary. Existing OpenTitan integration remains available and unchanged.

Owner, RUN and stop-request pass two synchronizer stages from video to lite.
Stop-ack and registered quiescence pass two stages back to video. Sensor grant
changes only with engine idle, PS SCL/SDA outputs released and physical lines
continuously high for 500 lite cycles (5 us). No grant means hardware forbids
an I2C command and no Ibex pin drive. Reclaim waits the same idle guard. Physical
IOBUF data is constant zero; only the selected owner's low-enable drives its T
pin. PS observes physical inputs continuously even while disconnected.

The I2C engine transmits address-W, register-high, register-low, then data (write)
or repeated START/address-R/data/NACK (read), followed by STOP. It samples ACK
and input data after synchronized SCL reaches high. Clock stretching delays each
high phase. Half-period clamps to at least 125 cycles at 100 MHz (<=400 kHz).
Whole transaction timeout is 1,000,000 cycles (10 ms). On NACK it generates STOP;
on a stuck clock it releases both outputs and reports timeout. Arbitration is
not needed behind the exclusive mux. No retry hides a failed exposure byte.

FSM: IDLE -> FREE -> START -> TX_LOW/HIGH -> ACK_LOW/HIGH, looping through
address/register/data bytes; reads continue RESTART_LOW/HIGH/START -> TX address-R
-> RX_LOW/HIGH -> NACK_LOW/HIGH; all normal/error exits use STOP_LOW/HIGH/RELEASE
-> IDLE. Timeout from any busy state releases directly to IDLE. An input start
is accepted only in IDLE. Completion is a single-cycle pulse; result/error flags
remain until the next accepted start. Reset releases both pins and invalidates
state. Phase counter counts clock cycles; byte index 0..4 and bit index 7..0
advance only on completed phases. Payloads are unsigned fixed-width bytes,
16-bit register/divisor and 32-bit elapsed/timer values; no DSP pipeline exists.

Native CSR accepts req&&gnt, replies once the next cycle and rejects misalignment,
partial writes and unknown offsets. No response backpressure exists in native
Ibex protocol. Command snapshots address/register/byte before the engine starts;
engine state survives CPU reset while CSR routing state resets with the core.
The existing configuration CDC and AXI master continue draining accepted writes.

## Local CSR and firmware

0x52000000 offsets: 00 identity 53454e31; 04 modulo-32 100MHz ticks;
08 status (RUN0, owner-request1, grant2, busy3, done4, NACK5, timeout6,
rejected7, restart-required8); 0c half-period; 10 command (start0/read1,
device[14:8]); 14 register16; 18 write-byte/read-result-byte; 1c firmware state.
State writes: 1 boot-ready/quiescent, 2 active, 4 quiesced (only RUN0/idle),
8 fault/disarm. State reads return ff04-format source status. Defaults:
half-period125, no grant/arm/boot-ready, quiescent1, restart-required1.

Native AE is separately linked in ae_live/ibex, retaining the imported R5
adapter scaffold and pure ae_core. Code/const in program URAM, data/ring/stack
in data URAM, compact initialized BRAM boot copy. Fast IRQ17 acknowledges the
existing snapshot pending bits and publishes FE events; main performs sensor
transactions. Stats use sequence-before/after coherence, FE extends modulo16,
and SOF brackets each exposure/gain write. Stale stats, missing FE/SOF, NACK,
timeout, readback mismatch or detected crossing publish a fail-stop fault.
The existing ae_core supplies target96/deadband8, bounded steps and four-FE
holdoff. The firmware writes and reads back real ISP AE-enable after ownership.
Sensor readback initializes VTS/exposure/gain. No fixture values are used.

The board clocks remain running while ownership transfers. Snapshot/config CDC
has no stopped-clock cancellation; host startup must leave video clock running.
An FE notification is not the physical CSI FE/latch boundary, so software
bracketing cannot establish atomic sensor exposure updates.

## Packaging and completion evidence

Preparation copies USB software and tests with source hashes, including Makefile
and the existing DMA-BUF broker implementation. Shared DMA-BUF is default;
marker/static diagnostics retain copy behavior. Linux executable builds accompany
the bitstream because software changes do not reside in the FPGA bitstream.
The packaged Linux handoff tool provides status/start/stop with bounded polling
and explicit PS-IIC/R5-exclusive startup precondition. It never launches R5 AE.

Focused verification owns I2C phases/errors/stretch, CSR/CPU reset, ownership
quiescence, native firmware and AE convergence, and existing USB retention tests.
Full build checks linked resources, timing, DRC/CDC, route completion and matching
bit/probes after focused gates pass. No hardware programming is part of this run.
