# Ibex QSPI offline package, 2026-10-31

Frozen candidate: `build/ibex_small/qspi_v3_20261031`. No hardware operation was
performed by this packaging worker; RAM boot and flash are separate Terra gates.

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| Production FSBL ELF | 413424 | `4ad2b98b8cc33c4fda6052aa0c4bf70998f12788e9bc8dc2109ba28de87a0168` |
| RAM FSBL ELF | 412624 | `254de87f1ca09ef9a55b3cf454db427bfb8812e152e0bb3b43e402e8615bead7` |
| Production BOOT.BIN | 9095472 | `5ad1efe24f535d9f08dbcf8f00984fcbb368ab6442e141d39f454be5ba63058c` |
| RAM BOOT.BIN | 9095384 | `8e6c83db0cacbb9a41410240e033c3b85881d3d1ebfae48e8b6488564d3abec7` |
| Both FIT image.ub | 15756124 | `46fc6c2b371e4f59ae9cde098a17b85ef5b680a1bf687aaafe68be17188851ad` |
| Both initramfs.cpio.gz | 4985686 | `8fd9dc1f29359496e5fc342767688bab1438a65af97de9e7bf8a03746a16b5c1` |
| Production QSPI_LINUX.bin | 28339036 | `929ebbf1118ccd9abefe6c0a8a4c5aa48b38e3f57678a47dba1a0fb6bef4cc74` |

BOOT stays below0xc00000. FIT stays below20MiB. The merged image ends at
28339036 and rounds to28377088 bytes for64KiB erase geometry, below32MiB.
The flash-restoration backup was independently checked by the hardware owner;
its full32MiB hash is `24c0e6c1a6071fd2d2d9742db27d91c8f590de24505c8c916bc2a554c46c90be`.

Both FSBLs pass the existing OCM layout checker (28 sections), contain the real
XIicPs polled master implementation and use the same prepared sources except
`xfsbl_qspi.c`. RAM breakpoint is `Sc130RamBootReady=0xfffc3928`. Production/RAM
banners contain build times13:40:17/13:40:24 from `xfsbl_main.c`'s
`__DATE__/__TIME__`; earlier first-compile hashes are superseded by this matrix.

The archived platform FSBL SHA341a987c...3f5a4a was proved to use GPIO bit-banging
at0xff0a02c8 and bank3 input0xff0a006c. It is not the new PS-IIC source described
by later historical README hashes and is not included in this candidate.
The isolated FSBL preserves generated DDR/PS sources/BSP, power/pipeline hooks
and DP clock-parent handling while adding current sensor code, official driver
and guarded100MHz IIC0 preparation. Neither variant contains an R5 partition.

The rootfs parser found one real source cpio stream and433 records. Counting
literal TRAILER strings in the compressed payload was an incorrect earlier way
to infer archive count. Every original gzip byte and cpio record is preserved.
The added overlay contains the tested v3 bridge/dp_smoke/handoff, the IIC guard,
sequential startup coordinator, patched init and standard console5:1/null1:3
nodes. No ttyPS0 node is hardcoded: the target driver uses dynamic235:0 and
devtmpfs is mounted before tty access.

Focused verification: six archive/layout/device-conflict tests and six startup
success/failure/order tests passed; native C tests passed reset-only Linux
preparation and FSBL PLL/fraction/lock/divider/reset safeguards. Shell syntax
passed. The static AArch64 Linux helper's QEMU no-argument usage path returned2
before any hardware access. Input manifests and all frozen v3 hashes passed;
FIT kernel/DT/rootfs extraction and embedded hashes passed. Kernel and DT are
identical to the source seeds. The only build diagnostic was GCC's note that
two LTO translation jobs were compiled serially.

RAM boot, automatic sensor/ISP handoff, native AE operation, production QSPI write, full-chip hash verification and a QSPI system-reset boot passed on hardware. See `build/ibex_small/board_reports/20261031_ae_usb/QSPI_PREP.md` for evidence. Physical power-off/power-on cold boot has not been tested. Known sustained USB ERROR buffers remain an unresolved risk and are not hidden.
