# Full camera project with RAW10 brightness statistics

This bundle contains the current camera hierarchy, existing RAW10 statistics
observer, LTM/TNR, PS block design, IP configurations and ISP/TNR CLI sources.
The device is `xczu4ev-sfvc784-2-i`, top is `camera_top`, and `SC130_UVC` is enabled.
Use Vivado **2025.1**, matching the canonical exported configuration scripts.

Prepare a new source snapshot from the repository:

```powershell
python tools/package_full_ae_project.py
```

The default destination is `build/full_ae`. It must not already exist. Use
`--destination <new-directory>` for another location. Source bytes are copied
unchanged and SHA-256 values are recorded in `source_manifest.json`. The helper
does not invoke Vivado or build software. Historical vendor duplicates, build
outputs, caches and firmware binaries are excluded.

Generate the project from the snapshot in a fresh Vivado batch session:

```powershell
vivado -mode batch -source build/full_ae/tools/create_full_ae_project.tcl
```

The script creates `build/full_ae/project/camera.xpr`, generates IP and BD output
products and a BD wrapper, updates compile order, checks syntax and records
`reports/generation_manifest.tcldict` inside the bundle. It refuses an existing
project destination and asserts that every run remains **Not started / 0%**.
It performs no synthesis, placement, routing, bitstream creation or board access.
No boot, kernel or application image is rebuilt.

After generation, reopen `project/camera.xpr` and audit its sources and memory
initialization paths after relocation before distributing an archive. Archive the
whole bundle, including project output products and canonical sources; disposable
logs and caches may be omitted. The Python helper does not create or validate a
zip. A source manifest records provenance, not a synthesis or physical result.

The six unchanged 64-KiB control segments are VDMA0 `0xA0000000`, capture0
`0xA0010000`, VDMA1 `0xA0020000`, capture1 `0xA0030000`, ISP `0xA0040000`, and
TNR `0xA0050000`. The existing statistics registers occupy ISP offsets
`0x200..0x244`, advertised by capability bit 4. The observer taps RAW10 at
`isp/PIPELINE_PATH/converter/control/statistics`; it does not control exposure.

CLI sources and their existing build instructions are in
`software/isp-control` and `software/tnr-control`. On a board already running a
compatible image, the existing commands include:

```sh
ispctl stats status
ispctl stats set enable 1
ispctl stats set region 3
ispctl stats set black 52
ispctl stats read
tnrctl status
```

These commands are usage examples; project generation does not execute them or
program hardware. Earlier AE test reports remain historical evidence and are not
new tests of this generated project.
