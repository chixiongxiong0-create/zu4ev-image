# 2026-10-30 Ibex ISP master implementation

This note records the implemented source contract and self-review. Focused
verification and the full FPGA build are owned by the independent verification
agent; their reports, rather than this note, establish pass/fail. No physical
hardware operation is part of this change.

## Changed source files

Paths are relative to the Ibex repository. Existing unrelated uncommitted work
is preserved, and the original ZU4EV platform source tree is not edited.

| File | Change |
|---|---|
| integration/small/rtl/ibex_sensor_i2c.sv | new bounded sensor register transaction engine |
| integration/small/rtl/ibex_sensor_ctrl.sv | new local CSR/timer, session and mux interlock |
| integration/small/rtl/ibex_small_system.sv | optional local sensor native-bus destination and ports |
| integration/small/rtl/ibex_isp_cfg_owner.sv | optional PS RUN/status/stop acknowledgement and reclaim guard |
| integration/small/board/ibex_board_debug.sv | enable and connect native sensor control |
| integration/small/board/prepare_ae_copy.py | isolated pin mux, USB runtime/test packaging, rebuild tools and manifests |
| integration/small/board/build_ae_board.tcl | native AE ROM is the default image |
| integration/small/board/ISP_MASTER.md | deployment, ownership, diagnostics and software build instructions |
| integration/small/board/README.md | link native controller flow, retain historical evidence |
| integration/small/ae_live/ibex/board.h | native map, mailbox and ring schema |
| integration/small/ae_live/ibex/main.c | real statistics/ISP control/I2C AE and lifecycle |
| integration/small/ae_live/ibex/start.S | startup and 32-entry Ibex vectored interrupt table |
| integration/small/ae_live/ibex/link.ld | separate ROM/data RAM and reserved mailbox/stack space |
| integration/small/ae_live/ibex/runtime.c | freestanding memcpy/memset |
| integration/small/tools/build_ae_live.sh | native firmware build with RV32 libgcc |
| integration/small/tools/ibex_isp_handoff.c | Linux status/start/stop utility |
| docs/superpowers/specs/2026-10-30-ibex-isp-master.md | frozen architecture and protocol |
| docs/superpowers/plans/2026-10-30-isp-master-dmabuf.md | implementation/verification tracking |
| docs/implementation/2026-10-30-isp-master.md | this traceability and self-review note |

Independent verification adds focused benches and scripts under
`integration/small/sim`; those files are owned and reported by the verification
agent and are not implementation-authored tests.

## Design to RTL mapping

| Requirement | Owning implementation | Review result |
|---|---|---|
| Real sensor read/write with 16-bit big-endian register address | ibex_sensor_i2c state_q/state_d and metadata/byte datapath | dedicated controller; no software waveform bit banging |
| Repeated START, final read NACK, STOP | RESTART, RX, NACK and STOP states | every normal/NACK exit releases through STOP |
| Bounded clock stretching/stuck bus | phase_ready and elapsed_q timeout | high phase waits sampled SCL; total timeout releases outputs with error |
| Single physical owner and open-drain pins | ctrl grant_o and copied soc_subsystem IOBUF T select | IOBUF I is constant0; PS release or Ibex pull-low exclusively selects T |
| Safe grant/reclaim | idle_cycles_q plus no busy/start and both PS outputs released | 500 lite cycles high/idle guard; no combinational owner-to-pin mux |
| CPU-only reset drains accepted I2C | engine/global reset separated from ctrl cpu_rst_ni | command arm clears; engine and grant remain until STOP/timeout |
| No stale RUN authorization after reset | seen_run_low_q, boot_ready_q, restart_q | a high RUN alone cannot rearm a restarted CPU |
| No old-quiescent or toggle-ABA reclaim | gate stop_pending_q, stop_q and ctrl stop_ack_q/quiescent_q | pending duplicate RUN0 is idempotent; RUN1 rejected until matching ack |
| No premature stop during exposure byte group | firmware checks RUN at sequence boundaries; controller permits armed completion | RUN0 waits for complete writes/readback before FW state4 |
| Real frame statistics and events | existing ibex_isp_snapshot plus native IRQ17/statistics function | sequence-before/after and valid checks; no fixture inputs |
| Real ISP configuration ownership | existing configuration CDC/master/gate plus live AE-enable write/readback | gate preserves existing ff00 and AXI transaction draining |
| AE policy preserved | imported ae_live/ae_core plus native main | target96, deadband8, step bounds and four-FE holdoff |
| Native interrupt ABI | 256-aligned 32x4-byte table, common full save/restore handler | Ibex MTVEC is fixed vectored; IRQ17 must enter table slot17 |
| Existing USB shared buffers included | copied upstream software, capture_broker.h and Makefile/tests | no new DMA or image-copy path introduced |

The I2C FSM has an explicit combinational next-state block and separate state,
timers, transaction metadata, byte/bit datapath and completion flag owners.
The CSR block separates synchronizers, mux/timer, firmware lifecycle, command
payload/results and native response ownership. Every register has one
procedural owner. Both modules preserve explicit reset/hold semantics. No
gen_top conversion is imposed on this SystemVerilog integration.

## Interface and response self-review

`EnableSensorControl` defaults to zero in the reusable system, so existing
memory/peripheral/ISP configurations retain their decode and reset behavior.
The disabled generate branch ties all new outputs inactive. The owner gate's
`EnableSensorOwnership` defaults to zero: ff00 retains its previous ABI and the
new CSR addresses remain normal downstream addresses. Existing named-port
instantiations may leave the new disabled inputs unconnected.

Local requests use req&&gnt acceptance, one registered response, and a saved
system destination until retirement. Writes require alignment and all byte
strobes. Unknown offsets and forbidden commands return errors. The new local
err_o is zero outside rvalid and is updated with the matching response. The
controller rejects commands before arm/grant and while the engine is busy.
The global engine reset is distinct from CPU routing reset, so accepted I2C
cannot be abandoned by CPU-only reset. Native configuration traffic retains
the existing independent drain behavior.

Owner/RUN/stop request and returned status pass synchronizers. Safety depends
on the single-bit stop acknowledgement and registered quiescence, not atomic
sampling of every status flag. Video/lite are generated from the same existing
MMCM and retain ordinary timing constraints; this change adds no broad false
paths or asynchronous clock groups. Physical sensor inputs use two stages.
Actual routed CDC/timing reports remain a required build gate.

## Reproducible deployment flow

1. Build native firmware with `bash integration/small/tools/build_ae_live.sh`.
   Keep its ELF, map and dense MEM image. Firmware globals/ring occupy data RAM;
   mailbox is reserved at 0x0023e000 and stack is below 0x0023c000.
2. Prepare a new destination using `prepare_ae_copy.py --destination PATH`.
   Set `IBEX_BOARD_COPY=PATH`, then source `build_ae_board.tcl` in Vivado. The
   independent build owner runs synthesis, route and final bitstream/probes
   after focused verification. Reprepare after any source fix; manifests must
   correspond to the final frozen firmware/RTL inputs.
3. In the bundle, `make -C software OUT=build-aarch64
   CC=aarch64-linux-gnu-gcc LDFLAGS=-static all` creates the USB bridge,
   DP utility and handoff executable. Native software tests use a separate OUT.
   `bash software/ibex-ae/build.sh` independently rebuilds the bundled firmware
   sources, linker script and converter with the selected RISCV_PREFIX.
4. Deploy the matching bit/probes, firmware ELF and Linux executables. The
   bitstream does not install the USB application. PS performs the existing
   sensor/camera/ISP startup; leave video clocks running and R5 AE stopped.
5. Stop all PS IIC/ISP writers and complete pending ISP commits. Run
   `ibex_isp_handoff start --ps-writers-stopped`. Its read-only PS IIC preflight
   and the hardware idle mux interlock guard actual transfer; RUN authorizes
   firmware without a JTAG RAM mailbox command.
6. Observe `ibex_isp_handoff status`. Before PS control resumes, run
   `ibex_isp_handoff stop` and wait for success. If start or stop fails, the tool
   prints actual owner/RUN/ack/idle/fault status and directs PS writers to stay
   stopped. It does not forcibly reclaim a nonquiescent controller.

## Verification status and unresolved risks

Implementation is available for independent verification; this note does not
claim the full FPGA build or board operation has passed. Verification exposed
and drove fixes for stop old-value/ABA races, freestanding runtime linkage and
the fixed-vectored MTVEC startup contract. Rebuilt frozen firmware and final
manifests must include those fixes.

Remaining physical risks include I2C pull-up/rise timing and actual 400kHz SCL,
sensor two-byte exposure atomicity/latch boundaries, real AE convergence,
USB/DP DMA-BUF driver behavior and throughput, and stopped-video-clock behavior
of the pre-existing CDC path. Software FE is a delivered notification, not a
physical CSI FE timestamp. CPU reset between exposure bytes can leave a partial
value; restart rereads it and never reports the interrupted proposal as applied.
The PS tool's explicit stopped-writers flag is an application precondition;
the tool cannot prevent an unrelated R5/PS program from writing behind it.
