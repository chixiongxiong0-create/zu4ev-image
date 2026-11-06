# NV12 AXI-Lite control contract
32-bit little-endian AXI-Lite, same video clock and synchronous reset. One write and one read outstanding, independent AW/W capture; B and R held stable under backpressure. Byte strobes apply to scratch/config registers. Undefined, unaligned, read-only writes and invalid commands return SLVERR. Read snapshots have no side effects.

| Offset | Access | Meaning |
|---|---|---|
| 00 | RO | ID 0x4e563132 |
| 04 | RO | version 2 |
| 08 | RW | bit0 frame IRQ enable, bit1 capture ENABLE (reset 0) |
| 0c | RO | bit0 completed frame pending, bit1 pool configuration ready, bit2 DMA IDLE |
| 10 | RW | configuration slot (0..3) |
| 14 | RW | DMA base (32 bits) |
| 18 | RW | stride |
| 1c | RW | consumer release tag |
| 20 | WO | full-strobe command: 1 configure slot, 2 take completed frame, 4 release held slot, 8 STOP |
| 24 | RO | pending frame base |
| 28 | RO | pending frame stride |
| 2c | RO | pending frame slot tag |
| 30 | RO | no-buffer drops |
| 34 | RO | failed writes/frames |

Read STATUS, then pending metadata, then TAKE. Metadata remains stable until TAKE. TAKE moves ownership to software, deasserts that frame's level IRQ, and does NOT free the slot. RELEASE is legal only after VCU input DQBUF. Config command on a busy/reserved/held slot returns SLVERR immediately; invalid geometry/overlap and invalid releases return SLVERR after the pool's synchronous error pulse. Configure scratch registers before COMMAND. WRITE_CAPTURE -> EXECUTE -> COMMAND_WAIT -> CHECK -> B_RESPONSE lifecycle keeps command effects single-shot; no new writes while an old B response is pending. AXI read/write channels can operate concurrently. Command handshakes and pool error pulse are separate cycles. Reset cancels local bus transactions and requires coordinated AXI/VCU shutdown; STOP is provided; reset must not be used instead of STOP while writes are outstanding.


## Safe stop sequence
1. Write COMMAND=8 with WSTRB=0xf (or clear CONTROL.ENABLE with byte0 enabled).
2. Poll STATUS bit2 until 1. STOP B response only acknowledges acceptance; it does not acknowledge AXI drain. If DDR withholds AWREADY/WREADY/BVALID, IDLE must stay 0 with no timeout-based buffer release.
3. Existing completed frames can still be read/TAKE/RELEASE while stopped. PL IDLE does not imply VCU has released previously submitted buffers.
4. Preserve configured DMA mappings for restart. Set CONTROL.ENABLE only after IDLE; restart during drain returns SLVERR without changing control. Capture resumes only at a later source SOF. STOP never resets buffer-pool ownership.
5. To free/reconfigure the complete mapping set, first obtain PL IDLE and VCU completion, then perform coordinated peripheral/pool reset. Re-enabling with stale mappings is forbidden. IDLE promises no future PL memory accesses only while ENABLE remains clear.

Repeated STOP is harmless. Already completed frame notifications are retained. Unfinished current frames are returned as failed only after all issued write responses. Disabled source frames are ignored rather than counted as no-buffer drops. Register command latency and read/write backpressure do not alter the data-path drain guarantee.
