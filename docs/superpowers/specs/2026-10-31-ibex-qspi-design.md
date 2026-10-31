# Ibex v3 persistent QSPI boot

The authorized result is a cold QSPI boot into the already tested v3 PL/native
AE firmware, original PS/FSBL camera initialization, Linux shared DMA-BUF bridge,
and automatic PS-to-Ibex ownership transfer. R5 has no boot partition and remains
stopped. The original ZU4EV tree is read-only throughout.

Use the existing standard-boot architecture: BOOT.BIN at flash offset zero with
production FSBL, PMUFW, v3 camera_top.bit, BL31 and U-Boot; Linux FIT at 0x00c00000
with an upper bound of 20 MiB. The board confirmed a single 32 MiB NOR, 64 KiB
erase blocks and boot-mode raw value 2. Existing U-Boot reads those final 20 MiB
to 0x10000000 and boots configuration conf-sc130. Rebuilding the PS bootloaders,
kernel or DT would add unnecessary change; replacing only the bitstream would
omit the authorized Linux behavior. This minimal repackaging approach is selected.

Read PMUFW/BL31/U-Boot from the original boot/prebuilt directory and Linux seeds
from firmware/linux. The archived FSBL is a GPIO sensor implementation and cannot
initialize the v3 hard-IIC wiring: rebuild FSBL independently from the retained
generated PS/DDR sources/BSP, current sensor source and official XIicPs driver.
Before any IIC register access, validate the board's integer locked IOPLL
(33.333333 MHz * 90 / 2 = 1500 MHz), select /15 /1 for 100 MHz and release only
IIC0 reset with readback. No PLL programming is allowed. Production/RAM prepared
sources differ only in the QSPI read entry; RAM validates the entire flow first.
Keep kernel, DT, ISP/TNR configuration and peripheral modules byte-identical.
Preserve every cpio stream. Parsing established that this actual seed has one
valid archive with 433 records and no static device nodes. The earlier inference
of two archives from raw TRAILER string counts was incorrect; BusyBox can contain
that string as file data. The parser supports concatenated archives regardless.
Append a small overlay containing the tested v3 bridge, dp_smoke and handoff,
and replace /init's two concurrent launches with one background coordinator.
Add only console c5:1/0600 and null c1:3/0666 device nodes; retain the devtmpfs
mount before tty use. ttyPS0 has dynamic major 235 on the target and needs no
static node. Conflicting existing device records are rejected.
That coordinator starts the existing bridge launcher, runs the original
ISP/TNR profile synchronously, confirms the bridge remains alive, prepares the
unused PS IIC0 reset if PM finalization reasserted it, then invokes handoff start
exactly once. Linux preparation requires PS owner/RUN0, no bound IIC0 driver, an
enabled inherited IOPLL clock with nonzero divider and lock; it preserves clock
configuration and every reset bit except IIC0. The handoff utility checks ISP commit idle, boot-ready,
and the inherited FSBL IIC clock/reset/idle state before ownership grant.

Profile/bridge failures do not authorize Ibex. A failed start requests the normal
bounded stop/reclaim sequence, reports cleanup failure if quiescence cannot be
proved, and never forces bus ownership or retries start. USB/DP continue where
possible and the console stays available. No startup script invokes flash tools.

Offline validation covers concatenated cpio/device preservation, startup ordering,
failure cleanup, input hashes, static AArch64 binaries, BIF partition list, FIT
extraction/hashes and flash-size bounds. Terra exclusively owns backup, QSPI write,
readback and cold-boot verification. The known USB ERROR buffers remain an explicit
unresolved risk and are outside this packaging change.
