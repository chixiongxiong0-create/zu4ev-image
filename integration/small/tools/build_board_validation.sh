#!/usr/bin/env bash
set -euo pipefail
# Use existing toolchain environment, or explicitly provide RISCV_PREFIX.
cd "$(dirname "$0")/.."
prefix=${RISCV_PREFIX:-riscv64-unknown-elf-}
out=${1:-../../build/ibex_small/board_validation}
mkdir -p "$out"
"${prefix}gcc" -Os -march=rv32imc_zicsr -mabi=ilp32 -msmall-data-limit=0 \
  -ffreestanding -fno-builtin -nostdlib -nostartfiles -Wl,--build-id=none \
  -T board_validation/link.ld board_validation/start.S board_validation/main.c \
  -o "$out/board_validation.elf"
"${prefix}objcopy" -O binary "$out/board_validation.elf" "$out/board_validation.bin"
python3 tools/bin_to_mem.py "$out/board_validation.bin" "$out/board_validation.mem"
echo "Board ROM: $out/board_validation.mem"
