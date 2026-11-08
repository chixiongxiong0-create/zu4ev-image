# FFC/DPC NV12 QSPI v1.1.0.0-rc1

This QSPI candidate combines the RAM-validated FFC/DPC bitstream with the
production FSBL, PMU firmware, BL31 and U-Boot from the preceding NV12 QSPI
image. Bootgen builds the five inputs from the production BIF with only the
PL input replaced. The Linux FIT retains the NV12 kernel, DTB and normal
startup coordinator and adds the calibration tools and tables. The candidate
has been checked offline. QSPI programming and boot verification are pending.
The prior intermittent Ibex AE startup trap remains open.

- Boot starts at offset 0. FIT starts at `0xc00000` on a 32 MiB NOR.
- Image size is 31,779,664 bytes and the 64 KiB-aligned erase end is `0x1e50000`.
- QSPI SHA256 is `0903b2e785b09a67b48ab816a876bf4bb1713769054f4b7fda6a8e9cc71a8c8a`.
- The release hardware archive includes the matching bitstream and Ibex ROM.

## Rebuild the FIT and combined image

Build the ARM64 control tools with `platform/zu4ev/software/isp-control/Makefile`.
Build `ffc_sensor_meta` from `integration/small/tools/ps_iic_probe.c` and place it
with `ffcctl`. Run the packager where U-Boot `mkimage` and `dumpimage` are available.

```sh
python3 platform/zu4ev/boot/package_ffc_ram.py \
  --seed build/nv12_platform/ram_candidate \
  --tools build/releases/v1.1.0.0-rc1/tools \
  --dpcctl build/releases/v1.1.0.0-rc1/tools/dpcctl \
  --production-boot build/releases/v1.1.0.0-rc1/boot/BOOT.BIN \
  --ffc-map docs/verification/mono-dpc-20261107/dark-2243.map \
  --dpc-map docs/verification/mono-dpc-20261107/dark.dpc \
  --output build/releases/v1.1.0.0-rc1/qspi
```

## Calibration

Both tables are included for manual activation. Match the dark table to the
same sensor, exposure, gain and thermal conditions before applying it. The
factory boot profile continues through the ordinary PS-to-Ibex handoff.

```sh
ibex_isp_handoff stop &&
ffcctl load /opt/sc130/dark-2243.map &&
dpcctl load /opt/sc130/dark.dpc &&
ibex_isp_handoff start --ps-writers-stopped
```

The recalibrated dark table reduced the left/right-quarter mean difference
from 8.788 RAW10 before FFC and 2.926 with the old table to 0.247 with the new
table. Each RAW10 measurement averaged 32 frames. The DPC table contains the
confirmed hot pixel at (1021, 472). See [DPC RAM validation](2026-11-07-mono-dpc.md)
and [calibration data](mono-dpc-20261107/dark-2243.json).
