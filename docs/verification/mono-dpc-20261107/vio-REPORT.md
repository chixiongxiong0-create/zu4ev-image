# Ibex CPU-only reset during DPC board validation

Vivado and hw_server both reported 2025.1. The loaded DPC bitstream and matching
probes exposed `ibex_debug_i/u_vio` and one `ibex_debug_i/reset_cpu` output at 0.
The existing AE store trap was read through JTAG AXI: state=5, fault=10,
mcause=7, mepc=0x0010061c, exposure=0x20d0, gain=0x3f.

PS had successfully reclaimed the idle sensor bus. Committed reset_cpu=1,
waited 50 ms in Tcl, committed reset_cpu=0, and read back 0. Firmware state
returned to WAITING with fault=0. After the normal PS handoff utility, state=3,
signature=600dae01 and records/IRQ advanced 0x0f36 -> 0x0fb2 in about one second.
FFC/DPC active tables and streaming frame counters remained intact.
The firmware handshake race was recovered from, not changed by DPC.
