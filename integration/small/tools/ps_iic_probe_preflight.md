# IIC0 preflight

The helper requires `--clock-confirmed [probe|mode-probe|standby|stream-on]` and exclusive
ownership. Before mapping or accessing IIC0 at `0xff020000`, it maps the known
always-on CRL_APB page at `0xff5e0000` read-only, reads IIC0_REF_CTRL at offset
`0x120` and RST_LPD_IOU2 at `0x238`, prints and flushes both values, and refuses
access unless CLKACT (bit 24) is set and IIC0 reset (bit 9) is clear. It never
writes clock/reset registers. The observed `01000500 / 0001fffc` state is rejected;
`01000500 / 0001fdfc` passes this gate.

This is a state check, not proof that the upstream clock source is live. Other
masters can gate the clock or assert reset after the check; exclusive ownership
must cover those controls too. A stalled MMIO instruction cannot be cancelled by
the polling deadline or a signal. No reference-clock frequency is assumed, and
the existing refusal of an uninitialized divisor/master configuration remains.

Focused host integration test (from repository root on Linux/WSL):

```sh
out=build/ibex_small/ps_iic_probe
gcc -std=c11 -Wall -Wextra -Werror -Dmain=probe_main -c integration/small/tools/ps_iic_probe.c -o "$out/preflight_main_host.o"
gcc -std=c11 -Wall -Wextra -Werror integration/small/tools/ps_iic_probe_preflight_test.c "$out/preflight_main_host.o" -Wl,--wrap=open,--wrap=flock,--wrap=mmap,--wrap=munmap,--wrap=close -o "$out/preflight_test_host"
"$out/preflight_test_host"
aarch64-linux-gnu-gcc -std=c11 -Wall -Wextra -Werror -O2 -static integration/small/tools/ps_iic_probe.c -o "$out/ps_iic_probe_crl_preflight_aarch64"
```

The test executes the real entry point with syscall wrappers, checks the CRL
mapping is read-only, and checks that rejected clock/reset combinations never
even map IIC0. The permitted combination reaches the real IIC snapshot and then
rejects an uninitialized controller without writes. These tests do not emulate
physical bus stalls or validate a sensor transaction on hardware.

`probe` remains the default: it reads ID bytes `3107/3108` and stream `0100`
from the fixed address `0x30`. `mode-probe` additionally reads only
`3018/3031/3208..320f`, printing the FSBL expected values
`30/0a/05 00 04 00/03 0c 02 11` alongside matches or mismatches; it does not
program a mode table. Mismatches are diagnostic and do not change the exit code.

`standby` and `stream-on` require both ID bytes to equal `01/30` and the current
stream value to be 0 or 1 before any sensor state write. This ID is a historical
observation on this board, not manufacturer identity authentication. They write
only `0100=0` or `0100=1`, respectively, then read it back; an already satisfied
state needs no write. Failure does not retry the write. Controller cleanup does
not undo the explicit sensor state change.

The state-command register-model test exercises the actual transaction code:

```sh
gcc -std=c11 -Wall -Wextra -Werror integration/small/tools/ps_iic_probe_state_test.c -o "$out/state_test_host"
"$out/state_test_host"
gcc -std=c11 -Wall -Wextra -Werror -O2 integration/small/tools/ps_iic_probe.c -o "$out/ps_iic_probe_state_guard_host"
aarch64-linux-gnu-gcc -std=c11 -Wall -Wextra -Werror -O2 -static integration/small/tools/ps_iic_probe.c -o "$out/ps_iic_probe_state_guard_aarch64"
```

Keep earlier probe binaries intact when building this version. The register
model verifies exact ID/state guards, fixed address/register writes, state
readback, no-op states, and failure without retry; it does not model electrical
IIC or pipeline/D-PHY sequencing. Pipeline restart and the standby interval are
controlled separately by the hardware owner.
