#!/usr/bin/env bash
set -euo pipefail
source /mnt/d/development/rtl/env.sh
cd "$(dirname "$0")/.."
mkdir -p ../../build/ibex_small/ae
riscv64-unknown-elf-gcc -Os -march=rv32imc_zicsr -mabi=ilp32 -ffreestanding -fno-builtin -nostdlib -nostartfiles -Iae -Wl,--build-id=none -T ae/link.ld ae/start.S ae/main.c ae/ae_core.c -lgcc -o ../../build/ibex_small/ae/ae.elf
riscv64-unknown-elf-objcopy -O binary ../../build/ibex_small/ae/ae.elf ../../build/ibex_small/ae/ae.bin
python3 tools/bin_to_mem.py ../../build/ibex_small/ae/ae.bin ae/ae.mem
