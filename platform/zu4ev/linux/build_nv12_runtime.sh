#!/bin/bash
# Build against the already-validated H264 kernel; never mutate its configuration.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd -- "$HERE/../../.." && pwd)
SRC=${SC130_KERNEL_SOURCE:-/home/developer/zu4ev/sc130-platform-build/linux-src}
KOUT=${SC130_H264_KERNEL_OUT:-/home/developer/zu4ev/sc130-h264-build}
OUT=${SC130_NV12_OUT:-$REPO/build/nv12_platform/runtime}
mkdir -p "$OUT/module" "$OUT/overlay/opt/sc130" "$OUT/overlay/usr/bin" "$OUT/overlay/etc"
cmp "$HERE/kernel/sc130_nv12_uapi.h" "$HERE/../software/nv12_capture.h"
cp "$HERE/kernel/sc130_nv12.c" "$HERE/kernel/sc130_nv12_uapi.h" "$OUT/module/"
printf 'obj-m += sc130_nv12.o\n' > "$OUT/module/Makefile"
make -C "$SRC" O="$KOUT" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- M="$OUT/module" modules -j"${JOBS:-2}" > "$OUT/kernel-build.log" 2>&1
cp "$OUT/module/sc130_nv12.ko" "$OUT/overlay/opt/sc130/"
make -C "$HERE/../software" OUT="$OUT/native-tests" test -j"${JOBS:-2}" > "$OUT/userspace-tests.log" 2>&1
make -C "$HERE/../software" OUT="$OUT/software" CC=aarch64-linux-gnu-gcc LDFLAGS=-static all -j"${JOBS:-2}" > "$OUT/userspace-build.log" 2>&1
cp "$OUT/software/sc130_platform_bridge" "$OUT/software/nv12_vcu_probe" "$OUT/overlay/usr/bin/"
cp "$HERE/start-platform.sh" "$OUT/overlay/opt/sc130/"
chmod +x "$OUT/overlay/opt/sc130/start-platform.sh"
printf 'SC130_USE_NV12=1\nUVC_FORMAT=h264\n' > "$OUT/overlay/etc/sc130-nv12.conf"
aarch64-linux-gnu-gcc -E -P -x assembler-with-cpp -nostdinc -undef -D__DTS__ \
 -DSC130_ENABLE_CAPTURE -DSC130_ENABLE_RAW_CAPTURE -DSC130_ENABLE_CONNECTOR_USB1_PS_USB0 \
 -I "$SRC/arch/arm64/boot/dts/xilinx" -I "$SRC/include" -I "$HERE/dt" \
 "$HERE/dt/sc130-nv12.dts" -o "$OUT/sc130-nv12.preprocessed.dts"
dtc -I dts -O dtb -o "$OUT/sc130-nv12.dtb" "$OUT/sc130-nv12.preprocessed.dts" 2> "$OUT/dtc.log"
aarch64-linux-gnu-readelf -h "$OUT/software/sc130_platform_bridge" | grep -q AArch64
printf 'NV12_RUNTIME_BUILD_PASS %s\n' "$OUT"
