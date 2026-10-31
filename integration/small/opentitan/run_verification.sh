#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$root"
: "${FUSESOC:=fusesoc}" "${VERILATOR:=verilator}" "${RISCV_PREFIX:=riscv64-unknown-elf-}"
"$FUSESOC" --cores-root=integration/small/opentitan run --target=default --tool=xsim --setup local:ibex:opentitan_peripherals
out=build/local_ibex_opentitan_peripherals_0.1/default-xsim
python3 - "$out" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]); lines=(p/'local_ibex_opentitan_peripherals_0.1.prj').read_text().splitlines()
files=[x.split(' ',2)[2].replace('\\','/') for x in lines if x.startswith('sv ')]
incs=['+incdir+src/lowrisc_prim_assert_0.1/rtl','+incdir+src/lowrisc_prim_secded_0.1/rtl','+incdir+src/lowrisc_prim_util_memload_0/rtl','+incdir+src/lowrisc_prim_fifo_0/rtl']
(p/'verilator.f').write_text('\n'.join(incs+files)+'\n')
files=['../../../'+x for x in pathlib.Path('integration/small/sources.txt').read_text().splitlines() if x.startswith('rtl/')]
files += ['../../../integration/small/opentitan/xpm_test_model.sv','../../../integration/small/rtl/ibex_small_core.sv','../../../integration/small/rtl/ibex_small_mem.sv','../../../integration/small/rtl/ibex_small_system.sv','../../../integration/small/opentitan/tb_system.sv']
(p/'system.f').write_text('\n'.join(files)+'\n')
PY
"${RISCV_PREFIX}gcc" -march=rv32imc_zicsr -mabi=ilp32 -nostdlib -nostartfiles -Wl,--build-id=none -T integration/small/sw/link.ld integration/small/opentitan/test_cpu.S -o "$out/cpu_test.elf"
"${RISCV_PREFIX}objcopy" -O binary "$out/cpu_test.elf" "$out/cpu_test.bin"
python3 integration/small/tools/bin_to_mem.py "$out/cpu_test.bin" "$out/cpu_test.mem"
"${RISCV_PREFIX}gcc" -march=rv32imc_zicsr -mabi=ilp32 -nostdlib -nostartfiles -Wl,--build-id=none -T integration/small/sw/link.ld integration/small/opentitan/test_uart_irq.S -o "$out/uart_irq.elf"
"${RISCV_PREFIX}objcopy" -O binary "$out/uart_irq.elf" "$out/uart_irq.bin"
python3 integration/small/tools/bin_to_mem.py "$out/uart_irq.bin" "$out/uart_irq.mem"
cd "$out"
"$VERILATOR" --binary --timing -Wno-fatal --top-module tb -f verilator.f ../../../integration/small/opentitan/tb_peripherals.sv -j 4
./obj_dir/Vtb
"$VERILATOR" --binary --timing -Wno-fatal --top-module tb_uart -f verilator.f ../../../integration/small/opentitan/tb_uart.sv -j 4
./obj_dir/Vtb_uart
"$VERILATOR" --binary --timing -Wno-fatal --top-module tb_system +incdir+../../../vendor/lowrisc_ip/dv/sv/dv_utils -f verilator.f -f system.f -j 4
./obj_dir/Vtb_system
"$VERILATOR" --binary --timing -Wno-fatal --top-module tb_uart_irq +incdir+../../../vendor/lowrisc_ip/dv/sv/dv_utils -f verilator.f -f system.f ../../../integration/small/opentitan/tb_uart_irq.sv -j 4
./obj_dir/Vtb_uart_irq
