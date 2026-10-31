# OpenTitan peripheral dependency import

Upstream: https://github.com/lowRISC/opentitan
Pinned revision: `8e7f977585b8e8304feaf688d7e8429059bfd097`

Run `python integration/small/opentitan/import_upstream.py` to obtain the full upstream source tree in `vendor/`. The importer refuses to overwrite any existing destination. Retaining the full tree preserves LICENSE, notices, generated RTL, FuseSoC core metadata, and transitive dependencies. Network access and sufficient disk space are required. The archive is selected by immutable Git commit; no independent archive digest has been recorded.

The checked-in `*.upstream.core` files are reference metadata copied verbatim from this revision; they are not standalone build cores. Use the original files inside vendor for builds, with vendor registered as a FuseSoC library. Do not add these metadata snapshots to an RTL source list.

## Implemented subsystem

`ibex_opentitan_peripherals.sv` instantiates the genuine pinned `rv_timer`, `i2c`, `uart`, and Earlgrey-generated `gpio` modules. `ibex_opentitan_peripherals.core` is the build manifest: register this directory and `vendor` as FuseSoC libraries and build `local:ibex:opentitan_peripherals`. Run `python integration/small/opentitan/prepare_metadata.py` once for an already imported checkout; fresh imports apply it automatically. This idempotent metadata-only adaptation replaces the obsolete aggregate TL-UL dependency in the four peripheral cores with the genuine register/RACL adapter dependencies; the wrapper declares host/socket dependencies directly. It avoids unrelated DMI/JTAG cores rejected by newer FuseSoC waiver schemas. Upstream functional RTL is unchanged.

The manifest explicitly selects the upstream Earlgrey top/RACL constants and generic primitive implementation, rather than local package or IP substitutes. Vendor contents remain ignored and must be imported on a fresh checkout.

| Native address window (64 KiB) | Upstream module |
| --- | --- |
| `0x40000000` | `rv_timer` |
| `0x40010000` | `i2c` |
| `0x40020000` | `uart` |
| `0x40030000` | `gpio` |

Register offsets and bit definitions are the pinned upstream register packages and documentation. GPIO uses the current Earlgrey register layout, including its per-pin register views. These are not legacy small-system register-compatible devices.

### Micro-Architecture

The wrapper uses one outstanding native request, `tlul_adapter_host` with command/data integrity generation and response integrity checking, and an upstream `tlul_socket_1n` to steer four destinations. The bridge accepts on `req_i && gnt_o`, holds its busy state until `rvalid_o`, and returns the upstream data/error response. The socket retains destination selection with its request FIFO and supplies the standard TL-UL error response for an invalid selection. Addresses retain their full value through the integrity-protected bus; the register blocks decode their own local register offsets.

All IP shares `clk_i` and active-low `rst_ni`. Reset flushes outstanding transactions; software must restart after reset. There is no new custom FSM: upstream bus adapters own request/response lifecycle. In the small-system integration, a pending bit and captured destination serialize memory and peripheral traffic, preventing response reordering. Pending state sets on accepted native requests and clears on the corresponding response. This deliberately permits a bubble between transactions. `EnablePeripherals=0` bypasses this routing and preserves the original memory path.

Timer interrupt connects to the core timer interrupt. The OR of all 15 I2C and 32 GPIO interrupt outputs connects to the core external interrupt (ORed with the existing external input). All 9 UART causes form a dedicated `irq_uart_o`, connected exclusively to Ibex `irq_fast_i[0]` while peripherals are enabled; the external input at bit 0 is reserved/ignored in that mode, while bits 14:1 are preserved. UART therefore uses machine interrupt cause 16 (`mcause` interrupt bit set, code 16), with `mie[16]` / `mip[16]`; it is excluded from the external interrupt aggregate. Timer retains machine timer interrupt cause 7, and I2C/GPIO use machine external interrupt cause 11. Software reads the respective upstream interrupt state registers to identify the internal source. With `EnablePeripherals=0`, all internally generated interrupt signals are zero and the complete original 15-bit fast interrupt input is preserved. GPIO inputs/outputs/enables and I2C inputs/outputs/enables are exposed separately; the upstream I2C output enables implement open drain and require board-level pullups. UART TX drives idle high. The FPGA top must connect these pins and enables to its chosen I/O buffers.

RACL is disabled by the upstream default parameters; policy inputs are zero. RAM configuration uses the upstream generic default zero request. GPIO strap sampling is disabled. Alert receivers use valid differential idle encodings, alert sender synchronizers are disabled because all logic is in one clock domain, and fatal alert outputs plus bridge integrity errors are exposed at `peripheral_alert_o`. This is an observable alert boundary without an OpenTitan alert handler, ping service, or security certification.

`ibex_small_system` exposes the pins and the default-disabled `EnablePeripherals` parameter. Enabling it requires including the manifest dependencies in the selected build; disabled legacy builds need not resolve the unelaborated peripheral branch.

### Validation ownership

Focused compilation and simulation are performed by the separate verification task. The implementation task has not run verification or claimed passing results. Required checks include reset, read/write/error handshakes, alternating memory/peripheral traffic, byte enables, peripheral interrupts and output enables. No FPGA implementation or hardware test is implied.
