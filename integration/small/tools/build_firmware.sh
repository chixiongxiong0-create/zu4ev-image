#!/usr/bin/env bash
set -euo pipefail
source /mnt/d/development/rtl/env.sh
cd "$(dirname "$0")/.."
mkdir -p ../../build/ibex_small
riscv64-unknown-elf-gcc -march=rv32imc_zicsr -mabi=ilp32 -nostdlib -nostartfiles -Wl,--build-id=none -T sw/link.ld sw/selftest.S -o ../../build/ibex_small/selftest.elf
riscv64-unknown-elf-objcopy -O binary ../../build/ibex_small/selftest.elf ../../build/ibex_small/selftest.bin
python3 tools/bin_to_mem.py ../../build/ibex_small/selftest.bin sw/selftest.mem
