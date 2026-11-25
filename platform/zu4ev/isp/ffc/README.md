# Mono FFC operation

FFC corrects smooth spatial offset and sensitivity variation on two RAW10 pixels
per video clock before BLC/LTM, raw AE statistics and TNR. See DESIGN.md for CSR
and cycle contracts. This is a coarse 32-pixel mesh, not individual pixel repair.

Dark-only calibration needs a light-tight cover. A full gain calibration additionally
needs an unsaturated uniform bright field. Never derive gains from a covered sensor.
Keep exposure, gain and temperature metadata alongside both acquisitions. Match
sensor settings between dark and flat. Pixel correction runs in PL; A53 only
loads a table or reads 1280 cell sums during explicit calibration.

Build `ffcctl` with the isp-control Makefile. After loading matching hardware:

```sh
ibex_isp_handoff stop
ffcctl status
ffcctl capture /tmp/dark.stats
# Under a uniform bright field, same fixed exposure/gain:
ffcctl capture /tmp/flat.stats
```

Host:

```sh
python platform/zu4ev/isp/ffc/calibrate.py --dark dark.stats \
  --output dark.map --report dark.json
# Full offset+gain calibration, when bright-field data exists:
python platform/zu4ev/isp/ffc/calibrate.py --dark dark.stats --flat flat.stats \
  --output flat.map --report flat.json
```

Board, while ownership is still PS:

```sh
ffcctl load /tmp/dark.map
ffcctl measure /tmp/corrected.stats
# Finish all PS ISP/sensor writes before restoring AE:
ibex_isp_handoff start --ps-writers-stopped
```

`load` checks the complete map before MMIO writes, reads every uploaded word
back, then waits for a frame-boundary apply. A failed/partial upload leaves the
active bank unchanged. Use `ffcctl disable` and wait for its successful completion
before retrying an incomplete upload. Old firmware without FFC must not be probed
at undefined extension offsets. Stop/reclaim Ibex first, including for status.
The tool shares ownership and ISP advisory locks with existing controllers.

Pedestal is 52 so the existing BLC still subtracts its normal 52 codes. Do not
also set BLC to zero without adjusting the rest of the transfer function. A
calibration obtained at one sensor gain/exposure is not automatically valid for
all AE operating points. Dark current, temperature and internal sensor correction
can change the measured offset. Keep bypass available and retain uncorrected data.

Validation commands:

```powershell
powershell -File tests/zu4ev/ffc/run.ps1 -Full
powershell -File tests/zu4ev/ffc/run_regs.ps1
python tests/zu4ev/ffc/test_calibrate.py
```

`platform/zu4ev/tools/build_ffc_project.tcl` clones the validated NV12 project,
keeps its existing BD/clock interfaces, restores the matching Ibex ROM and adds
canonical sources. It uses one build job to bound memory. Route timing/DRC/bus
skew gates must pass before accepting its bitstream. The RAM FIT packager is
`platform/zu4ev/boot/package_ffc_ram.py`; it adds acquisition tools and captures
one dark batch before the boot coordinator starts AE. The coordinator waits for
`touch /tmp/ffc-allow-ae` so original/corrected measurements retain fixed sensor
settings. Create that flag only after all PS calibration work completes. This acquisition image is
RAM-only and must not be treated as a production QSPI package.
