# Ibex v3 QSPI package

`build_ibex_qspi.ps1` performs offline builds only. It builds production and RAM
FSBLs, adds v3 Linux software and a sequential boot coordinator, then builds FIT
and merged QSPI images. It never connects to a board or writes flash.

```powershell
./integration/small/boot/build_ibex_qspi.ps1
```

Defaults use the frozen `build/ibex_small/isp_master_v3_20261030/deliverables`,
read-only ZU4EV platform boot/Linux inputs and an independent output directory
`build/ibex_small/qspi_v3_20261031`. Override `-Platform`, `-Bundle`,
`-OutputDirectory` and `-Bootgen` as needed. Required tools are Windows Vitis
2025.1 bare-metal AArch64 GCC/Bootgen and WSL AArch64 Linux GCC, Python,
mkimage/dumpimage/fdtget. The FSBL driver default is the installed official
`D:/Xilinx/2025.1/data/embeddedsw/XilinxProcessorIPLib/drivers/iicps_v3_21/src`.

The source platform's archived FSBL hash
`341a987c8f448c6d88bdab087094844c4d0402255176608b53a0eabd9f3f5a4a`
is an older GPIO implementation, as verified by its sensor bit-banging
disassembly. Historical hashes in its FSBL README describe other builds. This
package does not use that ELF. It retains generated DDR/PS initialization and
BSP libraries, but compiles current PS IIC0 sensor code plus official XIicPs.
The isolated addition validates locked integer IOPLL FBDIV90/DIV2 with the
board's 33.333333 MHz reference, derives 100 MHz using divisors15/1, readbacks
the reference change and releases only IIC0 reset. An unexpected PLL fails
before IIC access. Source hashes and prepared copies accompany each ELF.

Linux startup is `/init` -> background `/opt/sc130/start-ibex-platform.sh` ->
existing bridge launcher (whose final action is `exec` bridge) -> synchronous
PS ISP/TNR profile -> guarded IIC reset preparation -> one handoff start.
The profile itself waits for capture statistics. The handoff utility keeps
all existing commit/clock/reset/idle/boot guards. Failed start requests bounded
stop/reclaim, reports an incomplete stop, and never retries or forces ownership.
No R5 partition is present. The console remains available.

The original compressed rootfs is retained byte-for-byte with a second gzip/cpio
overlay. The actual seed has one valid cpio archive/433 records; the parser also
supports multiple archives. Only standard console/null nodes are added. `/init`
mounts devtmpfs before accessing a tty; no guessed static ttyPS0 is installed.

Per-variant `manifest.json`, `boot-inputs.json` and `SHA256SUMS` identify output
bytes. Kernel and DT stay unchanged, and every FIT payload is extracted and
checked against its source and embedded SHA-256. Flash layout is BOOT@0 below
12 MiB and FIT@0xc00000 below the final20 MiB of a32 MiB NOR. The two FSBL
prepared trees differ only in `xfsbl_qspi.c`; the RAM build also enables its
staging breakpoint. RAM U-Boot boots the FIT staged at0x10000000; production
U-Boot reads it from QSPI. FSBL banners use `__DATE__/__TIME__`, so recompilation
changes ELF hashes. Freeze the tested outputs and use their final manifests.

For RAM testing, use `fsbl-ramtest/fsbl_sc130.elf` and its actual
`Sc130RamBootReady` symbol from `symbols.txt`, `ramtest/BOOT.BIN`,
`ramtest/image.ub` and `ramtest/inputs/pmufw.elf`. The hardware owner must
validate complete FSBL sensor initialization, Linux startup/profile/IIC handoff,
native AE progress and the stopped R5 before flashing the production variant.
The RAM variant is never the production flash image.

Focused tests run without hardware:

```sh
python3 -B -m unittest discover -s integration/small/boot/tests -p 'test_*.py' -v
cc -O2 -std=c11 -Wall -Wextra -Werror integration/small/boot/tests/test_iic_prepare.c -o /tmp/test_iic_prepare
/tmp/test_iic_prepare
cc -O2 -std=c11 -Wall -Wextra -Werror integration/small/boot/tests/test_fsbl_iic_clock.c -o /tmp/test_fsbl_iic_clock
/tmp/test_fsbl_iic_clock
sh -n integration/small/boot/start-ibex-platform.sh
```

Known sustained120fps USB ERROR buffers remain unresolved; this packaging task
does not change USB behavior or suppress counters. Hardware RAM/flash results
are recorded separately in the board report.
