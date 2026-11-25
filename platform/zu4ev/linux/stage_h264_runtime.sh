#!/bin/bash
# Stage the two modular VCU drivers plus capture modules; other dependencies
# are built into the matching configuration. Never overlay unrelated modules.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
OUT=${SC130_H264_KERNEL_OUT:-/home/developer/zu4ev/sc130-h264-build}
DEST=${1:-$OUT/minimal-overlay}
RELEASE=$(cat "$OUT/include/config/kernel.release")
MODULES=$DEST/lib/modules/$RELEASE
mkdir -p "$MODULES/kernel/drivers/clk/xilinx" \
 "$MODULES/kernel/drivers/media/platform/allegro-dvt" "$DEST/opt/sc130" \
 "$DEST/lib/firmware" "$DEST/usr/share/licenses/vcu-firmware"
cp "$OUT/drivers/clk/xilinx/xlnx_vcu.ko" "$MODULES/kernel/drivers/clk/xilinx/"
cp "$OUT/drivers/media/platform/allegro-dvt/allegro.ko" "$MODULES/kernel/drivers/media/platform/allegro-dvt/"
cp "$OUT/modules.builtin" "$OUT/modules.builtin.modinfo" "$MODULES/"
printf '%s\n' kernel/drivers/clk/xilinx/xlnx_vcu.ko kernel/drivers/media/platform/allegro-dvt/allegro.ko > "$MODULES/modules.order"
cp "$OUT/capture-module/sc130_capture.ko" "$OUT/capture-module/sc130_raw.ko" "$DEST/opt/sc130/"
cp "$HERE/setup_uvc.sh" "$HERE/start-platform.sh" "$DEST/opt/sc130/"
chmod +x "$DEST/opt/sc130/"*.sh
test -s "$OUT/firmware-verified/manifest.json" || python3 "$HERE/fetch_vcu_firmware.py" "$OUT/firmware-verified"
cp "$OUT/firmware-verified/al5e.fw" "$OUT/firmware-verified/al5e_b.fw" "$DEST/lib/firmware/"
cp "$OUT/firmware-verified/LICENSE" "$OUT/firmware-verified/manifest.json" "$DEST/usr/share/licenses/vcu-firmware/"
depmod -b "$DEST" "$RELEASE"
printf 'H264_RUNTIME_STAGED %s\n' "$DEST"
