# TNR control

Build with `make` using `aarch64-linux-gnu-gcc`; the default output is a static executable at `../../build/ae_stats/software/tnrctl`. Install as `/usr/bin/tnrctl` on the board. Root access to `/dev/mem` is normally required.

The default register base is `0xA0050000`, mapped for 64KiB. Options `--base PHYS`, `--dev PATH`, and `--lock PATH` precede the command. Numbers are decimal or `0x` hexadecimal. The default exclusive advisory lock is `/run/lock/tnrctl.lock`; only the default lock creates `/run/lock`. All programs accessing these registers must use the same lock.

```
tnrctl status
tnrctl bypass
tnrctl memtest
tnrctl set alpha 192
tnrctl set motion-low 6
tnrctl set motion-high 20
tnrctl enable
tnrctl clear
tnrctl read 0x24 4
```

`set enable 0|1`, `set alpha 0..256`, `set motion-low 0..254`, and `set motion-high 1..255` update shadows. `apply` snapshots all shadows; low must be less than high. `enable` and `bypass` set the enable shadow and apply **all** shadow settings. `clear` queues a history clear with the existing active settings, leaving uncommitted shadows alone. Each successful commit clears history and increments applied sequence. These commands wait up to one second for the sequence change at a safe frame boundary. A timeout can leave a pending request; inspect status before retrying.

Clear TNR history after changing upstream LTM mode, bank, or gain. The next enabled frame seeds history without temporal filtering. Reset defaults to bypass; calibration alone does not enable TNR.

`memtest` requires active enable zero, DDR calibration complete, no pending commit, and no active memory test. It waits up to ten seconds and reports error count; nonzero errors or timeout return failure. Run `bypass` first. The memory test overwrites history memory. Repeated tests must expose a busy/done transition to distinguish new completion from stale done; if a transition is missed, the CLI conservatively times out. Parent memory arbitration is responsible for draining outstanding memory work before the test.

`read OFFSET [COUNT]` and `write OFFSET VALUE` provide aligned 32-bit accesses inside the mapping. Raw writes bypass software guards; hardware rejects read-only, unmapped, and invalid values with AXI SLVERR, which may cause SIGBUS on Linux. Avoid undefined offsets. The complete register map is in `docs/tnr/design.md`. Parsed argument ranges and mapping alignment are validated before opening a lock or device.
