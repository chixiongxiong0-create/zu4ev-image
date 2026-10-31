# Native Ibex ISP/AE runtime

This source bundle keeps the PS camera startup, DDR/capture, DP and USB path.
The Ibex image controls real ISP AE statistics and SC130 exposure/fine gain
after an explicit PS handoff. It does not contain an R5 AE runtime. R5 must
remain stopped while Ibex owns the sensor. The original platform tree is not
modified. No hardware execution is claimed by an offline build.

Build the native firmware in the Ibex repository:

```sh
source /mnt/d/development/rtl/env.sh
bash integration/small/tools/build_ae_live.sh
```

The resulting `build/ibex_small/ae_live/ae_live.{elf,bin,mem,map}` use RV32IMC,
program/data URAM and a compact BRAM boot copy. `build_ae_board.tcl` selects
this native image by default. `IBEX_BOARD_ROM` can still select an explicit
legacy image; a legacy image does not run this controller. Prepare a fresh
destination with `prepare_ae_copy.py --destination PATH`; set `IBEX_BOARD_COPY`
to that path before sourcing `build_ae_board.tcl` in Vivado.

The Linux software is a separate deliverable from the FPGA bitstream:

```sh
cd software
make OUT=build-aarch64 CC=aarch64-linux-gnu-gcc LDFLAGS=-static all
make OUT=build-host test
```

Deliver `build-aarch64/sc130_platform_bridge`, `dp_smoke` and
`ibex_isp_handoff` alongside the matching bitstream/probes and native AE ELF.
The USB bridge defaults to shared V4L2 DMA-BUF capture buffers. Broker holds
keep a source buffer out of capture reuse until both DP and USB retire it.
Sequence-marker and static USB diagnostic modes retain the copy path. The
packaged software README is updated to describe the shared default.
No new frame-copy DMA is required, and a bitstream alone cannot install the
Linux software changes.

After booting the matching platform and initializing the original PS camera
pipeline, stop every R5/PS IIC0 and ISP configuration writer. Leave video/lite
clocks running; complete any pending ISP frame-boundary commit. Keep the
USB/DP capture consumers running if desired. Then run as root:

```sh
./ibex_isp_handoff status
./ibex_isp_handoff start --ps-writers-stopped
```

The explicit option records that the application has stopped its writers;
the utility cannot identify arbitrary independent R5 or PS software. It checks
PS IIC0 clock/reset read-only, HOLD/bus-active/TX-FIFO idle, ISP identity/commit,
firmware boot-ready and a fresh quiescence acknowledgement before granting
ownership. It never rewrites clock divisors, sensor mode tables or IIC0 state.
The physical pin mux additionally requires both PS outputs released and both
lines high continuously for 5 us. Once ownership and grant are confirmed,
RUN authorizes native firmware automatically; no JTAG RAM command is needed.

Startup validates historical board ID `0130`, stream-on, VTS/exposure/gain,
enables/readbacks the live ISP AE control, and reads coherent RAW10 statistics.
It retains the existing target96/deadband8 policy, bounded exposure/gain steps,
four-FE holdoff, readback and detected FE/SOF boundary fail-stop checks. Sensor
ID is a board guard, not manufacturer authentication. A software FE notification
is later than the physical CSI FE, so these checks do not prove a physical
sensor latch boundary or atomic two-byte exposure update.

Before any PS writer resumes, stop and reclaim through the same utility:

```sh
./ibex_isp_handoff stop
```

RUN0 lets the firmware complete its entire current byte group and readback.
The PS-visible stop toggle/ack prevents an old quiescent value from granting
premature reclaim. The gate rejects owner0 while a stop acknowledgement is
pending. Duplicate RUN0 writes while pending are idempotent; RUN1 is rejected
until the stop completes. After firmware quiescence, the tool reclaims ISP,
waits for the idle-guarded sensor mux to return to PS, and exits. It times out
after 2 seconds rather than stealing an active bus. Fault/stop status is
readable at ISP PS base `0xa0040000` + `ff00/ff04/ff08` even while Ibex owns ISP.

CPU-only VIO reset leaves accepted I2C transfers running through STOP or the
10 ms timeout and releases both Ibex pull-low enables afterward. It revokes
arming and publishes restart-required. Stop/reclaim with the utility after
reset, then start a new session. A stale RUN1 cannot restart AE. A reset during
a two-byte exposure can leave a partial sensor value: the fresh session rereads
both bytes; it does not assume the abandoned proposal applied. Full coordinated
reset resets both the camera register crossing and the sensor controller.

Native diagnostics live at Ibex RAM `0x0023e000`, with schema in
`software/ibex-ae/board.h`; the ELF locates the 512-record ring. `600dae01` means
sensor/ISP initialization completed, not that AE converged. Advancing records,
statistics and verified sensor changes are separate evidence. PS handoff
`status` reports boot/armed/fault/quiescent without needing JTAG. Firmware faults
are latched until CPU reset. Measured electrical I2C timing, sensor latch
behavior, image convergence and USB/DP performance remain physical board tests.

The source manifest lists original source SHA-256 values. The integration
manifest records final patched files and Ibex source inputs. Keep both with
the bitstream build reports and deployed software.
