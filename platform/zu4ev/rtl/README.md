# Camera hierarchy

The subsequent QSPI deployment and camera capture validation passed; see
`reports/hierarchy_refactor/qspi/RESULTS.md`. Earlier validation-stage descriptions
below retain their original scope.

`camera_top` is the normal synthesis entry. It retains the board ports of
`sc130_camera_top_v2`; that old module is a forwarding compatibility wrapper.

| Direct child | Source | Ownership |
| --- | --- | --- |
| `platform` | `platform/platform.v` | Differential reference buffer, camera clocks, resets, TNR memory bridge and its existing CDC/MIG path |
| `soc_subsystem` | `soc/soc_subsystem.v` | `ps_system` and open-drain camera I2C output routing |
| `sensor_rx` | `sensor/sensor_rx.v` | CSI control, CSI receiver, PHY-fault synchronizer |
| `isp` | `../isp/isp.v` | Capture frontend (global/LTM) and optional TNR |
| `video_capture` | `capture/video_capture.v` | Shared source sequence/timestamp, two capture phases, guards and register banks |
| `debug_monitor` | `debug/debug_monitor.v` | Monitor, GPIO synchronizers, diagnostic pipeline, atomic snapshots and ILAs |

The ISP and capture children are selected by `SC130_UVC`. Without that define,
the original CSI-only receiver and diagnostic behavior remains the selected path.
The top is interconnect only. Existing sequential blocks are moved with their
original reset expressions and initial values; the refactor adds no pipeline stage.

## Interfaces and compatibility

* `isp` retains its original first twelve ports and `BYPASS` parameter. Its
  default `PIPELINE=0` branch instantiates the original RAW10 converter with the
  original READY behavior. New control, memory and fault ports are appended.
* `PIPELINE=1` selects the former dual-capture frontend/TNR path. `USE_LTM`,
  `USE_TNR`, `ISP_RUNTIME`, `LINE_WORDS` and `FRAME_LINES` retain the old capture
  selection and geometry semantics. This broadcast path accepts each source beat
  and ignores downstream READY exactly as the previous capture integration did.
* The production `camera_top` instantiates `isp` and `video_capture` separately.
  `uvc_capture_dual` is a test-only compatibility wrapper in
  `sim/hierarchy/compat/uvc_capture_dual.v`; it keeps the former public interface
  for the hierarchy and AE equivalence simulations and is excluded from normal
  recursive production source discovery.
* `video_capture` consumes a 32-bit converted stream, valid/SOF/EOL, and aligned
  packet/global faults. DMA monitor inputs and both capture control interfaces
  retain their widths and meanings.
* Sensor pixels remain two RAW10 values in the low 20 CSI data bits. Diagnostic
  packing remains two zero-extended 16-bit slots. The GPIO snapshot index 0–17,
  marker `0x53433130`, reset-status bits, and GPIO open-drain polarity are retained.

## Address map and build integration

The PS block design and address assignments are unchanged:

| Region | Base | Range |
| --- | --- | --- |
| VDMA 0 | `0xA0000000` | 64 KiB |
| Capture 0 | `0xA0010000` | 64 KiB |
| VDMA 1 | `0xA0020000` | 64 KiB |
| Capture 1 | `0xA0030000` | 64 KiB |
| ISP | `0xA0040000` | 64 KiB |
| TNR | `0xA0050000` | 64 KiB |

`tools/add_hierarchy_sources.tcl` adds Verilog/SystemVerilog recursively from
`rtl` and `isp`, rebinds copied RTL to this checkout, and selects `camera_top`.
The normal reconstruction, prepare and build scripts source this helper. Internal
VDMA probes now use `soc_subsystem/ps_i/...`. Board pin constraints are unchanged;
the existing hierarchical `*gc1_reg*` synchronizer constraint also covers the
extracted debug block. Build scripts use `camera_top.bit` for Vivado's generated
file and retain their existing published artifact names.

An isolated legacy ISP simulation can still compile only `isp.v` and its RAW10
converter dependencies with `PIPELINE=0`. An isolated `uvc_capture_dual`
simulation must explicitly include `sim/hierarchy/compat/uvc_capture_dual.v`,
`rtl/capture/video_capture.v` and the ISP frontend
sources needed by its selected parameters.

## Validation status

The Astra low coding subagent performed no verification. The primary agent ran
four cycle-by-cycle pre/post integration comparisons (global, LTM, TNR and
combined), legacy ISP tests, both UVC/CSI-only debug comparisons, source
preservation checks, and full synthesis with the actual IPs. See
`reports/hierarchy_refactor/RESULTS.md` for evidence and limits. No hardware was
reprogrammed and no firmware artifact was changed. These checks do not establish
physical or bitstream equivalence.

The subsequent physical build also passed placement, routing and artifact checks:
setup +0.288 ns, hold +0.010 ns, DRC errors0. Reports and retained methodology
warnings are documented in `reports/hierarchy_refactor/RESULTS.md`. New bit/XSA/LTX
files are separate in `build/hierarchy_refactor/artifacts`; the board was not
reprogrammed.
