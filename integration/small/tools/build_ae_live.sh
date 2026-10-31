#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
prefix=${RISCV_PREFIX:-riscv64-unknown-elf-}
out=${1:-../../build/ibex_small/ae_live}
mkdir -p "$out"
"${prefix}gcc" -Os -march=rv32imc_zicsr -mabi=ilp32 -msmall-data-limit=0 \
  -Wall -Wextra -Werror -ffreestanding -fno-builtin -nostdlib -nostartfiles \
  -Wl,--build-id=none,-Map,"$out/ae_live.map" -T ae_live/ibex/link.ld \
  -I ae_live -I ae_live/ibex ae_live/ibex/start.S ae_live/ibex/main.c ae_live/ibex/runtime.c ae_live/ae_core.c \
  -lgcc -o "$out/ae_live.elf"
"${prefix}objcopy" -O binary "$out/ae_live.elf" "$out/ae_live.bin"
python3 tools/bin_to_mem.py "$out/ae_live.bin" "$out/ae_live.mem"
"${prefix}size" "$out/ae_live.elf"
echo "Native ISP master ROM: $out/ae_live.mem"
