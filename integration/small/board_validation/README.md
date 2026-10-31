# Real ISP board validation firmware

This image observes the real snapshot CSR, not the AE fixture. It never accesses
sensor/I2C registers, acknowledges FE/SOF, commits configuration, or requests
ownership. Build in a configured RISC-V GCC shell:

```
bash integration/small/tools/build_board_validation.sh
```

The optional first argument is an output directory relative to integration/small.
`RISCV_PREFIX` overrides `riscv64-unknown-elf-`. In Vivado set environment
`IBEX_BOARD_COPY` to the isolated camera tree and `IBEX_BOARD_ROM` to the absolute
generated board_validation.mem path before sourcing board/build_ae_board.tcl.
The wrapper's RomFile parameter is configurable; that script stages the chosen
image as a compact board_rom.mem, defines IBEX_BOARD_ROM_FILE and derives
IBEX_BOARD_BOOT_WORDS after validating the entire input. Only trailing zero words
are removed; hardware zero-fills the rest of the 256 KiB program UltraRAM before
releasing CPU reset (131072 clocks). The current image contains 251 boot words. With no selection the
script stages the existing ae.mem, preserving the previous board choice.

Mailbox base is CPU/JTAG RAM address **0x0023f000**; see protocol.h for its exact
word layout. PS has no direct RAM bridge in this integration: the application's
PS handoff and JTAG mailbox operations must be coordinated externally.

1. Wait for magic 0x49564231, version 0x00010000, size 0xac. Startup clears host
   commands, authorization and old completion; heartbeat must advance. If reset
   interrupted a dirty test, before/dirty and ERR_RESTORE remain for recovery.
2. Ensure video clock is running and will remain running. Write 0x56494431 to
   video_ready (+0x2c). The image now publishes real coherent result statistics,
   FE/SOF counters and pending flags without acknowledging them. Publication is
   stable only when publish_seq (+0x1c) is the same even value around a RAM read.
   Snapshot retries are bounded to eight; ERR_SNAPSHOT flags exhausted retries.
3. For ID/version/capability reads, PS must stop its entire configuration
   sequence, wait for outstanding frame-boundary commits, grant owner through
   0xA004ff00 and read back 1. Firmware publishes owner and actual ID. The owner
   gate denies all ordinary ISP reads before this grant, including ID.
4. Only if explicitly authorizing the shadow-black test: after owner grant,
   write command (+0x20)=0x54455354, then a fresh request (+0x24) unequal to ack.
   PS must keep ownership and stop configuration until completion. The test
   requires no pending commit, saves shadow-black (ISP offset 0x14), writes a
   legal adjacent value, reads it back, restores the original and verifies it.
   It never writes commit 0x20, active settings, statistics configuration or LUT.
5. Wait ack (+0x28)==request, state COMPLETE (6), signature 0x600dcf01 and dirty
   (+0x50)==0. Check errors and all before/trial/observed/restored fields.
   First stop firmware polling before PS reclaims: write video_ready=0 and read
   back 0, keep the actual video clock running, then read publish_seq/heartbeat,
   wait, and read heartbeat/publish_seq again. Require the same even publish_seq
   and an advancing heartbeat, with ready still 0, ack==request, dirty==0 and no
   errors/trap. `board/read_validation.tcl` provides `ibex_validation::pause`
   for this check. Completion ack alone does not stop later owner/ID reads;
   reclaiming during those reads can cause an Ibex access-fault trap. Only after
   polling is quiescent may PS reclaim and read back owner 0. Write video_ready
   back to its magic value to resume observation after verifying the source
   clock/reset state. No other host may change readiness/request or reset the
   CPU during this software pause check. A failed request is acknowledged with
   FAILED (7); sticky errors explain it. A trap halts in TRAPPED (8), saves
   mcause/mepc/mtval and never publishes successful completion.

No software loop can time out an MMIO access when video clock stops. Do not
reclaim owner, reset only CPU, or stop that clock during a test. A dirty failure
requires manual PS recovery using the saved before value after safely draining
traffic; CPU reset does not roll back an accepted write. This mailbox proves
observation/shadow-register restoration, not live AE algorithm migration or
active frame-boundary configuration changes. Firmware itself does not run a
test until the explicit command is supplied.
