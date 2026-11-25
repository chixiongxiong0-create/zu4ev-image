# ZU4EV camera platform source snapshot

## H.264 UVC development branch

The H.264 extension adds VCU hardware encoding and real frame-based H.264 UVC
descriptors. DP still imports the original YUY2 capture buffers; compression
uses separate NV12 input and encoded output buffers. The A53 performs YUY2-to-NV12
conversion (NEON on AArch64), not H.264 compression. Its 120 fps CPU cost is an
explicit hardware acceptance item. USB stop does not stop capture or DP.

`linux/setup_uvc.sh` defaults to H.264; `UVC_FORMAT=yuy2` and the bridge's
`--usb-format yuy2` select the legacy recovery path together. Never send H.264
with a YUY2 descriptor. The H.264 path requires the matching VCU bitstream,
`linux/vcu-allegro.dtsi`, UVC patches 0007–0009, Allegro patch 0010, the upstream
Allegro driver and matching firmware; see `linux/VCU_PREREQUISITES.md`.

Build recipes are `linux/build_h264_kernel.sh` and the existing Ibex board build
with the updated `hardware/ps_system.tcl`. Offline QSPI packagers are
`integration/small/boot/build_h264_boot.ps1` and `package_h264_qspi.py` in the
parent repository. They preserve the production versus RAM-test boot distinction
and never program flash. Their output is not evidence of board validation.

The imported `source_manifest.json` below identifies the frozen baseline only;
it does not describe later H.264 changes. New artifacts need their own hashes.

This directory publishes the source used by the frozen Ibex ISP-master v3
integration. It contains camera/ISP RTL, hardware/IP configuration Tcl,
constraints, Linux applications and tests, custom kernel modules/patches/DT,
and the application sources used to rebuild the production FSBL. No Vivado
project output, bitstream, ELF, object, SDK library or Linux image is included.

The full development report is [the repository homepage](../../README.md).
The original platform overview is [README.upstream.md](README.upstream.md).
[THIRD_PARTY.md](THIRD_PARTY.md) describes copyright and license boundaries.

| Directory | Contents |
|---|---|
| `rtl/`, `isp/` | Integrated camera/ISP source, including the PS/Ibex ownership and open-drain pin connections; LUT `.mem`/`.coe` files are source initialization tables |
| `hardware/`, `constraints/` | Re-creatable IP/block-design configuration and board/DDR constraints |
| `software/` | Shared DMA-BUF bridge, DP support, controls, tests and copied native Ibex AE sources |
| `linux/` | Custom capture module source, DT, kernel patches, scripts and tests; the complete Linux kernel is external |
| `tools/` | Platform project-generation helpers |
| `boot/` | Original boot/FSBL preparation and build source; generated application source is under `firmware/boot_reference/zynqmp_fsbl/` |
| `boot/fsbl/prepared/` | Exact prepared production FSBL application source, including current sensor code and the small official XIicPs driver subset |
| `boot/fsbl/ramtest/xfsbl_qspi.c` | The only prepared-source difference for the RAM test variant; use the production source as its base |

The main Ibex integration remains maintained under
[`integration/small`](../../integration/small). The copies in this directory
retain the final v3 content; in particular `software/ibex-ae` and
`software/ibex_isp_handoff.c` mirror that integration. R5 AE and GPIO sensor
utilities are retained as reference source and are not the active production
path. Current AE uses the native sensor controller, not the optional OpenTitan
peripheral block. Shared DMA-BUF operation adds no RTL image-copy DMA.

## Provenance and verification

[`source_manifest.json`](source_manifest.json) lists all 297 imported files by
relative path, byte count, SHA-256 and logical source. The exporter takes the
union of the frozen v3 `source_manifest.json` and
`integration_manifest.json` file lists and verifies each selected file against
the final recorded hash. It also imports a fixed bounded list of boot/Linux
sources and the exact FSBL prepared list. No generated Vivado directory is
searched. Only a source-listed `.vscode/settings.json` was excluded as editor
configuration. Original headers, SPDX tags and source bytes are retained.

The source-only exporter is
[`export_platform_source.py`](../../integration/small/tools/export_platform_source.py).
It requires the local frozen source/FSBL packages to export a new independent
directory. It refuses to overwrite an existing publication directory. The
manifest records logical origins rather than workstation paths. The README,
third-party notice and manifest itself are publication metadata, separate from
the imported-file hash list.

## Build boundaries

Linux application tests can run directly on Linux/WSL:

```sh
make -C platform/zu4ev/software OUT=/tmp/zu4ev-software-tests CC=gcc test
```

For a fresh FPGA build, first build the native AE image using
`integration/small/tools/build_ae_live.sh`. Copy this platform source to a new
working directory outside the published snapshot, set `IBEX_BOARD_COPY` to
that copy, and source `integration/small/board/build_ae_board.tcl` in Vivado
2025.1. The current source already contains the Ibex integration patches:
**do not run `prepare_ae_copy.py` against it again**, since that preparer expects
an unmodified upstream camera platform. Ibex upstream/vendor sources are
provided by the parent repository, and Xilinx IP/XPM implementations come
from the installed tools.

The existing QSPI build accepts `-Platform`, `-Bundle` and `-OutputDirectory`
in `integration/small/boot/build_ibex_qspi.ps1`. Its original defaults are
unchanged to protect the tested local flow. To rebuild using this published
platform path, supply the following external inputs in a separate working copy:

- Matching generated FSBL BSP `include/` and `lib/` at
  `firmware/boot_reference/zynqmp_fsbl/zynqmp_fsbl_bsp/psu_cortexa53_0/`.
- The pinned boot prebuilt seed files and manifest under `boot/prebuilt/`
  (PMUFW, BL31, U-Boot and the remaining manifest members).
- The pinned Linux kernel, DTB, initramfs, ITS and manifest under
  `firmware/linux/`. The module source is present here; the full matching
  kernel source/configuration is an external dependency for a kernel rebuild.
- A bundle/deliverables directory containing the matching FPGA bitstream,
  native AE ELF/mem/map and static AArch64 applications with `SHA256SUMS`.
- Vitis/Vivado 2025.1, its AArch64 bare-metal compiler and official XIicPs
  source, WSL AArch64 Linux GCC and U-Boot image tools.

The prepared FSBL source is included for exact code review even without those
external BSP libraries. Rebuilding introduces the FSBL `__DATE__/__TIME__`
banner; it does not promise the same ELF hash as the previously tested build.
The RAM FSBL and RAM U-Boot are test artifacts and must not replace the
production variants. Full RAM boot and the authorized hardware owner's
flash/readback/reset checks remain required for a new image. The known USB
ERROR-buffer risk remains documented in the development report.
