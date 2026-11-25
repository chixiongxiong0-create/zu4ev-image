#!/bin/bash
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SRC=${SC130_KERNEL_SOURCE:-/home/developer/zu4ev/sc130-platform-build/linux-src}
OUT=${SC130_H264_KERNEL_OUT:-/home/developer/zu4ev/sc130-h264-build}
BASE=${SC130_BASE_KERNEL_OUT:-/home/developer/zu4ev/sc130-platform-build/kernel}
[[ "$OUT" != "$BASE" ]] || { echo 'Separate H264 output required' >&2; exit 2; }
mkdir -p "$OUT"
python3 "$HERE/apply_h264_uvc_patches.py" "$SRC"
for patchfile in "$HERE"/patches/*.patch; do
 case ${patchfile##*/} in 0007-*|0008-*|0009-*) continue ;; esac
 if ! patch --batch --dry-run -R -p1 -d "$SRC" < "$patchfile" >/dev/null 2>&1; then
  patch --batch --forward -p1 -d "$SRC" < "$patchfile"
 fi
done
[[ -s "$OUT/.config" ]] || cp "$BASE/.config" "$OUT/.config"
"$SRC/scripts/config" --file "$OUT/.config" -e V4L_MEM2MEM_DRIVERS -m VIDEO_ALLEGRO_DVT -m XILINX_VCU
make -C "$SRC" O="$OUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
make -C "$SRC" O="$OUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"${JOBS:-8}" Image modules
make -C "$SRC" O="$OUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH="$OUT/modules-root" modules_install
mkdir -p "$OUT/capture-module" "$OUT/runtime-overlay/opt/sc130"
cp "$HERE/kernel/"*.c "$HERE/kernel/"*.h "$HERE/kernel/Makefile" "$OUT/capture-module/"
make -C "$SRC" O="$OUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- M="$OUT/capture-module" modules
cp "$OUT/capture-module/"*.ko "$OUT/runtime-overlay/opt/sc130/"
cp "$HERE/start-platform.sh" "$HERE/setup_uvc.sh" "$OUT/runtime-overlay/opt/sc130/"
chmod +x "$OUT/runtime-overlay/opt/sc130/"*.sh
cp -a "$OUT/modules-root/lib" "$OUT/runtime-overlay/"
python3 "$HERE/fetch_vcu_firmware.py" "$OUT/firmware"
mkdir -p "$OUT/runtime-overlay/lib/firmware" "$OUT/runtime-overlay/usr/share/licenses/vcu-firmware"
cp "$OUT/firmware/"*.fw "$OUT/runtime-overlay/lib/firmware/"
cp "$OUT/firmware/LICENSE" "$OUT/firmware/manifest.json" "$OUT/runtime-overlay/usr/share/licenses/vcu-firmware/"
aarch64-linux-gnu-gcc -E -P -x assembler-with-cpp -nostdinc -undef -D__DTS__ \
 -DSC130_ENABLE_CAPTURE -DSC130_ENABLE_RAW_CAPTURE -DSC130_ENABLE_CONNECTOR_USB1_PS_USB0 \
 -I "$SRC/arch/arm64/boot/dts/xilinx" -I "$SRC/include" -I "$HERE/dt" \
 "$HERE/dt/sc130-h264.dts" -o "$OUT/sc130-h264.preprocessed.dts"
dtc -I dts -O dtb -o "$OUT/sc130-h264.dtb" "$OUT/sc130-h264.preprocessed.dts"
printf 'H264_KERNEL_BUILD_PASS %s\n' "$OUT"
