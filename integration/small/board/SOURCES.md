# ZU4EV fixed-configuration Ibex source profile

`../board_sources.txt` is the explicit source list for `ibex_small_core`:
RV32IMC, RegFileFF, ICache=0, ICacheECC=0, ICacheScramble=0, SecureIbex=0.
It preserves the Ibex RTL files and removes unused lowRISC primitive library
implementations from the project, not from disk. The generic `../sources.txt`
and the complete vendor library remain available for other configurations.

The five retained `prim_` sources are:

- `prim_ram_1p_pkg.sv`: types used in `ibex_top` ports, even with no ICache.
- `prim_secded_pkg.sv`: constants referenced by Ibex source.
- `prim_util_pkg.sv`: utilities referenced by the retained source modules.
- `prim_buf.sv`: actual Ibex top-level buffer instances.
- `prim_clock_gating_ultrascale.sv`: board binding for `prim_clock_gating`.

Headers such as `prim_assert.sv` are resolved through include directories;
absence of a hardware instance is not a reason to delete a package or header.
Changing the core configuration requires revisiting this profile and rerunning
elaboration, simulation and synthesis. This is a board profile, not a generic
replacement for the upstream dependency list.

## Apply and rebuild

In an idle, writable Vivado project containing the fixed board configuration:

```tcl
source <repo>/integration/small/board/apply_sources.tcl
```

The script validates paths before changing the fileset, prunes only lowRISC
primitive `.sv` module/package entries, preserves headers, and adds the selected
board dependencies. Repeating it is idempotent. It does not reset runs, change
defines, regenerate IP or delete repository files. Project fileset changes may
mark existing synthesis/implementation runs out of date.

`build_ae_board.tcl`, `platform/zu4ev/tools/build_nv12_project.tcl` and the
directed `integration/small/tools/run_xsim.tcl` use this same profile. Generic
simulation flows continue to use the complete dependency list.

## Validation, 2026-11-05

The NV12 project originally contained 109 `prim_` source entries. Applying the
profile to an isolated copy removed 104, leaving five. Full `camera_top` RTL
elaboration completed with no errors, no critical warnings, and zero blackboxes.
The directed XSim test produced all three terminal checks:

```text
IBEX_AXI_PASS boundaries alignment backpressure write_reject concurrency collision
IBEX_MEMORY_PASS all_16_byte_masks boundaries errors reset
IBEX_SMALL_PASS signature=600d600d reads=5 writes=6 errors=2
```

The two reported errors in the CPU test are expected injected bus errors,
checked by the testbench. The test validates CPU execution, memory and AXI
behavior; it is not a new sensor/VCU/USB board test. Hardware RTL is unchanged.

Evidence: `build/ibex_small/xsim/ibex_small.sim/sim_1/behav/xsim/simulate.log`
and the isolated `build/nv12_sources_min/` project/reports. Full camera_top synthesis completed successfully with zero errors, zero
critical warnings and 195 ordinary warnings. After IP linking, no unresolved
RTL modules remained. The only synthesis blackbox was Vivado-generated
`dbg_hub` (`REF_NAME=dbg_hub_CV`), verified against `get_debug_cores`. AMD UG908
[documents this expected debug-hub placeholder](https://docs.amd.com/r/en-US/ug908-vivado-programming-debugging/Implementing-the-Design-Containing-the-Debug-Cores); it is implemented before placement/routing.
This placeholder is not a missing lowRISC dependency.
The original build/nv12_platform/project/nv12.xpr now contains the same five
prim_ sources; top, defines, part, ROM path, IP list and constraints are unchanged.
The project was closed after saving so the GUI can reopen it. The original XPR
backup and source_audit.json are under build/nv12_sources_min. No placement,
routing, bitstream generation or board programming was repeated.
