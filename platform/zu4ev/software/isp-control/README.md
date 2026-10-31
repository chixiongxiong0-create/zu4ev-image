# Linux ISP and sensor controls

Build in Ubuntu 24.04 with `make -C software/isp-control` (cross GCC package
`gcc-aarch64-linux-gnu`). Outputs are static AArch64 ELF executables in
`build/ae_stats/software`. Override `CC=gcc LDFLAGS=` for a native build.
All command options precede the command. `--help` documents all commands.

Typical board commands (no deployment or hardware access performed here):

```
ispctl status
ispctl set mode ltm
ispctl set black 52
ispctl set gain 256
ispctl set sigma 64
ispctl apply
ispctl curve-default
ispctl apply --swap
ispctl curve-load /tmp/custom-curve.txt
ispctl apply --swap
ispctl read 0x34 4
ispctl write 0x10 2
sensorctl read 0x3107 2
sensorctl read 0x3e01 3
sensorctl write 0x3e01 0x10
```

The curve file has exactly 1024 whitespace-separated decimal or `0x` prefixed
values, each 0..1023. Plain hexadecimal without `0x`, COE syntax and comments
are not accepted. The entire file is validated before any MMIO write. The
factory curve matches `isp/ltm/generate_tone_rom.py` exactly, including the
971 white point and half-up integer rounding. Loading writes and reads back
the inactive bank without swapping; apply --swap explicitly commits it.
`apply` submits a frame-boundary request and waits up to 1000ms for both pending
to clear and applied_seq to increment (including 32-bit rollover). It polls with
1ms nanosleep intervals and returns an error on timeout. A timeout does not cancel
the hardware request: inspect status before retrying. A stalled pipeline can leave
the request pending. Do not submit another request then.

The default advisory locks are `/run/lock/ispctl.lock` and
`/run/lock/sensorctl.lock`; use one consistent lock path for all users of each
block. When the default lock is used, each tool creates /run/lock with mode0755
if missing (for tmpfs /run after boot). An explicit --lock path requires its
parent directory to exist. Help and invalid arguments create no directories.
Kernel drivers and unrelated /dev/mem tools do not honor these locks.
Real MMIO requires root or equivalent device access. Raw ISP commands allow
all aligned words within the 64KiB span; hardware rejects undefined addresses,
RO writes and invalid values. A bus error may terminate the process with
SIGBUS. Raw commands intentionally bypass the pending guard.

Sensor operations match FSBL GPIO protocol: 7-bit address 0x30, 16-bit register,
8-bit value, GPIO bank 3 bit0 SCL / bit1 SDA. Release means OEN=0; low means
OEN=1 and a masked low-data write. Non-I2C direction/output-enable bits and
non-I2C data bits are preserved. Original direction/OEN bits 0/1 are restored
on normal exit, including I2C failure. Data latch bits 0/1 remain low for open
drain operation. An external kill/signal/crash can interrupt a transaction;
there is no claim of electrical rollback or arbitration with another master.
The tool checks idle, detects NACK, bounds stretch waiting to 100 polls per
edge, attempts STOP on transaction errors, and never performs automatic bus
recovery or retries. Unlike the boot configuration helper it reports a reset
write NACK as an error; no reset-specific acceptance workaround is assumed.

Host tests use regular-file mmap, never real GPIO. They cover MMIO bounds,
setting encodings, all 1024 factory curve values, complete-file prevalidation,
raw top-of-span access, explicit swap, sensor invalid inputs, NACK/error
cleanup, GPIO preservation and exclusive-lock failure. They cannot prove AXI
SLVERR behavior, safe-frame timing, electrical I2C timing, ACK success or real
sensor image behavior; these require board validation after integration.

Black level and the LUT are independent: changing shadow black does not regenerate
the factory curve. curve-default always uses the fixed white=971 curve.

The new switch registers require matching PL and R5 builds. `ispctl ae enable 0|1`
pauses or resumes exposure control; statistics and FE interrupts continue. A
transaction already started when disabled is allowed to complete. `ispctl set blc
0|1` and `ispctl set tone 0|1` set shadow switches; `ispctl apply` commits them
at the existing safe frame boundary. Disabled BLC uses an effective black level
of zero without discarding the programmed black value. Disabled tone passes the
black-corrected original through the processing pipeline. `ispctl status` reports
shadow and active switch values when supported. TNR uses `tnrctl enable` and
`tnrctl bypass` and remains independent. The ISP bypass mode `raw` independently
bypasses black subtraction. RAW10 statistics use their own black setting.

Capability bit 5 advertises the R5 AE control register at offset 0x248; bit 6
advertises BLC shadow/active switches at 0x5c/0x60; bit 7 advertises tone
shadow/active switches at 0x64/0x68. On older designs these addresses are not
safe to access. Do not deploy the new R5 ELF with a bitstream lacking bit 5.


To repack the reference Linux FIT in Ubuntu: python3 tools/package_isp_control_linux.py.
Output: build/ae_stats/qspi/image.ub and linux-control-manifest.json.
The helper preserves original cpio records, kernel, DTB and ITS, adds /usr/bin
executables and verifies extracted FIT data plus SHA256 hashes. Needs mkimage,
dumpimage and fdtget. Does not build BOOT.BIN or access a board.


RAW10 statistics (firmware capability bit4 required):

```
ispctl stats status
ispctl stats set enable 1
ispctl stats set region 3
ispctl stats set black 52
ispctl stats read
```

Regions 0/1/2/3 are centered area 1/4, 1/2, 3/4, full. Settings latch on the next
RAW SOF independently of ISP apply; multiple settings are separate writes and
can straddle a frame boundary. `stats read` returns the last valid publication,
including its exact configuration and ROI, with at most 16 sequence retries.
Validity is checked before and after the snapshot, including late frame errors
that invalidate an already published result without changing its sequence.
An unavailable result or exhausted retries is an error. `stats status` shows
requested settings, SOF-latched enable, valid/busy and live error counters.
The commands check the legacy capability register before touching the new bank,
so unsupported firmware is rejected without an unmapped statistics read.
Statistics black subtraction is independent of ISP black/gain/curves and
sensor exposure. See `isp/ae/README.md` for the complete register contract.
