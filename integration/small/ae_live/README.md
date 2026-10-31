# SC130 live AE port scaffold

main.c and ae_core.* derive from software/r5-ae in the ZU4EV platform.
The policy, sensor startup/readback, IRQ acknowledgment, frame extension,
dropped-frame counters, ring records, and fail-stop fault paths are retained.
The R5 interrupt-init fault retains its numeric AE_ERR_GIC_INIT name for log compatibility.
No hardware adapter, board configuration, startup or linker script is supplied.
This is not a runnable or validated board image.

Required ae_board_config.h definitions: AE_GPIO_BASE, AE_ISP_BASE,
AE_NO_FRAME_TIMEOUT_TICKS (one second in the platform tick domain).
Unused legacy IIC/IRQ macro aliases in main.c do not establish a hardware map.

The adapter must provide ordered 32-bit MMIO; a monotonic modulo-32 timer;
bounded delays; interrupt initialization, enable/disable with compiler and CPU
ordering barriers; and bounded I2C operations returning zero on success.
Sensor reads require a 16-bit big-endian register address and repeated start.
I2C initialization reports the actual SCL frequency. No PS XIicPs/GIC/CP15
implementation may be used directly on Ibex.

The MMIO bridge must preserve the original GPIO register contract: bank 3
masked low writes at +0x18, direction +0x2c4, output enable +0x2c8;
status at +0x74 contains Gray FE[15:0], Gray SOF[29:16], pending[30].
FE ack toggles bit 13. Snapshot request toggles bit 2 with index[12:8];
+0x70 returns the selected snapshot after the 1 us handshake delay.
Snapshot indices 18/19 and 20/21 expose coherent FE/SOF timestamps.
ISP registers: capability +0x08 bit5, identity +0x200=0x41455331,
valid +0x210 bit0, sequence +0x214, frame +0x218, mean +0x21c,
AE enable +0x248 bit0. Clock-domain crossing and coherent snapshot semantics
must be implemented in RTL before attaching this firmware.

Memory sizing must include the 512-entry 68-byte record ring (34816 bytes),
stack, code, and globals. RV32 needs compiler runtime support for 64-bit
division in ae_core.c plus memset. Port verification is delegated to the
integration owner; no build or execution claim is made here.

Host verification sources (not run during implementation):

    cc -std=c11 -Wall -Wextra -Ihost -I. host/test_port.c ae_core.c -o test_port
    cc -std=c11 -Wall -Wextra -I. host/test_ae_core.c ae_core.c -o test_ae_core
    cc -std=c11 -Wall -Wextra -I. host/test_ae_loop.c ae_core.c -o test_ae_loop

Run these commands from ae_live, then execute each produced binary. The host
configuration uses deliberately synthetic addresses and must never be placed
on a board include path. test_port checks adapter error propagation, stats,
FE wrap extension, acknowledgment timeout, and ring wrap. Imported R5 tests
cover policy and closed-loop convergence. The complete main-loop fail-stop,
interrupt races, CDC and physical timing still require integration tests.
