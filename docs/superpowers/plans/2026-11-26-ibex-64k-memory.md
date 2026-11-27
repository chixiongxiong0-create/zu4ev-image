# Ibex 64 KiB program/data memory

## RTL coding request for TraeCLI

Implement only the RTL and RTL focused test changes below. Do not modify firmware, Vivado generated output, build directories, or Git history. Do not launch a full build. Return changed files and test results to the coordinating agent.

- `integration/small/rtl/ibex_small_mem.sv`: program and data each 64 KiB, 16384 x 32 bits. Program base 0x00100000, data base 0x00200000. Strict high-address decode `[31:16]`, word address `[15:2]`, 14-bit addresses; retain byte writes/AXI protocol/CPU reset behavior. Both XPM MEMORY_SIZE values 524288, ADDR_WIDTH_A/B 14. Legacy block ROM depth 16384. Boot ROM copy and zero fill exactly 16384 words; boot counter 14 bits, increment sized 14, terminal 14'h3fff; default BootImageWords 16384 and reject above 16384. Preserve boot readiness and loader behavior. Move input mailbox to 0x0020f000 through 0x0020f7ff, preserving output half read-only on host writes. No aliased access to prior 256 KiB region.
- `integration/small/rtl/ibex_small_system.sv`: BootImageWords default 16384; retain peripheral decode and interfaces. `ibex_small_loader.sv`: FirmwareBytes default 0x00010000. Check matching loader parameter overrides if any.
- Focused test updates in `integration/small/sim`: update program/data boundary expectations, last word addresses, AE mailbox from 0x0023e000 to 0x0020e000 and input/output mailbox from 0x0023f000/0x0023f800 to 0x0020f000/0x0020f800. Update BootImageWords in tb_uram_cpu. Add focused checks for program/loader last word and first invalid word, data read/write first invalid word, no wraparound, and boot readiness exactly after 32768 copy cycles. Test output mailbox write rejection and byte writes remain intact. Coordinate firmware and image generation with parent; don't run tests requiring outdated firmware.

Parent will update firmware linker/host tools/boot images, run focused XSim regressions, and integrate via Vivado. Preserve top interfaces; do not alter unrelated RTL.
