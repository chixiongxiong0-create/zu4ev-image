#!/bin/sh
set -eu
# Only this named gadget is managed. No recursive deletion and no USB2 preview.
ROOT=${CONFIGFS_ROOT:-/sys/kernel/config/usb_gadget}
G=$ROOT/sc130_platform
F=$G/functions/uvc.usb1
fail() { echo "sc130-uvc: $*" >&2; exit 1; }
put() { printf '%s\n' "$2" > "$1"; }
test_mode=${SC130_TEST:-0}
format=${UVC_FORMAT:-h264}
case "$format" in h264|yuy2) ;; *) fail "UVC_FORMAT must be h264 or yuy2" ;; esac
case ${1:-} in
prepare)
    : "${USB_VID:?Set your authorized USB_VID}" "${USB_PID:?Set your authorized USB_PID}"
    [ ! -e "$G" ] || fail "gadget already exists; stop bridge and run stop first"
    if [ "$test_mode" != 1 ]; then
        [ "$(id -u)" = 0 ] || fail "root required"
        [ -d /sys/kernel/config/usb_gadget ] || fail "mount configfs and enable UVC function first"
    fi
    mkdir -p "$G/strings/0x409" "$G/configs/c.1/strings/0x409" "$F"
    put "$G/idVendor" "$USB_VID"; put "$G/idProduct" "$USB_PID"
    put "$G/bcdUSB" 0x0300; put "$G/bcdDevice" 0x0200
    put "$G/bDeviceClass" 0xef;put "$G/bDeviceSubClass" 2;put "$G/bDeviceProtocol" 1
    put "$G/max_speed" super-speed
    put "$G/strings/0x409/manufacturer" "SC130 project"
    put "$G/strings/0x409/product" "SC130 DP USB120 Tone"
    put "$G/strings/0x409/serialnumber" "${USB_SERIAL:-SC130-PLATFORM-001}"
    put "$G/configs/c.1/strings/0x409/configuration" "USB1 SuperSpeed UVC"
    put "$G/configs/c.1/MaxPower" 250
    mkdir -p "$F/control/header/h" "$F/control/class/ss"
    mkdir -p "$F/control/terminal/camera/default" "$F/control/processing/default"
    put "$F/control/header/h/bcdUVC" 0x0110
    put "$F/control/terminal/camera/default/bmControls" 0
    put "$F/control/processing/default/bmControls" 0
    # The backported frame-based format uses its default descriptor and has
    # no color_matching allow_link callback. Set it before format creation,
    # since the kernel rejects writes once its reference count is nonzero.
    color=$F/streaming/color_matching/default
    if [ "$format" = yuy2 ]; then color=$F/streaming/color_matching/yuy2; fi
    mkdir -p "$color"
    put "$color/bColorPrimaries" 1
    put "$color/bTransferCharacteristics" 1
    put "$color/bMatrixCoefficients" 1
    if [ "$format" = h264 ]; then
        [ "$test_mode" = 1 ] || [ -d "$F/streaming/framebased" ] || fail "kernel lacks framebased UVC; apply supplied 0007/0008 patches"
        fmt=$F/streaming/framebased/h264
    else
        fmt=$F/streaming/uncompressed/yuy2
    fi
    mkdir -p "$fmt/1280x1024" "$F/streaming/header/h" "$F/streaming/class/ss"
    frame=$fmt/1280x1024
    # Configfs expects a binary 16-byte GUID.
    if [ "$format" = h264 ]; then
        printf '\110\062\066\064\000\000\020\000\200\000\000\252\000\070\233\161' > "$fmt/guidFormat"
        # Frame-based bBitsPerPixel is read-only and defaults to zero.
        [ "$test_mode" = 1 ] || [ "$(cat "$fmt/bBitsPerPixel")" = 0 ] || fail "unexpected framebased bBitsPerPixel"
        put "$frame/dwBytesPerLine" 0
        # Queue capacity (0009 patch); absent from the framebased USB descriptor.
        [ "$test_mode" = 1 ] || [ -w "$frame/dwMaxVideoFrameBufferSize" ] || fail "kernel lacks framebased buffer capacity patch 0009"
        put "$frame/dwMaxVideoFrameBufferSize" 2621440
        put "$frame/dwMinBitRate" 1000000
        put "$frame/dwMaxBitRate" 100000000
    else
        printf '\131\125\131\062\000\000\020\000\200\000\000\252\000\070\233\161' > "$fmt/guidFormat"
        put "$fmt/bBitsPerPixel" 16
        put "$frame/dwMaxVideoFrameBufferSize" 2621440
        put "$frame/dwMinBitRate" 1258291200
        put "$frame/dwMaxBitRate" 2516582400
    fi
    put "$frame/wWidth" 1280;put "$frame/wHeight" 1024
    put "$frame/dwDefaultFrameInterval" 83333
    printf '83333\n166667\n' > "$frame/dwFrameInterval"
    if [ "$format" = yuy2 ]; then ln -s "$color" "$fmt/color_matching"; fi
    ln -s "$fmt" "$F/streaming/header/h/$format"
    ln -s "$F/streaming/header/h" "$F/streaming/class/ss/h"
    ln -s "$F/control/header/h" "$F/control/class/ss/h"
    put "$F/streaming_interval" 1
    if [ "$format" = h264 ]; then
        # Match the H264 PROBE payload (8192 B), allowing deeper request queues.
        put "$F/streaming_maxpacket" 1024;put "$F/streaming_maxburst" 7
    else
        put "$F/streaming_maxpacket" 3072;put "$F/streaming_maxburst" 15
    fi
    ln -s "$F" "$G/configs/c.1/uvc.usb1"
    [ "$test_mode" != 1 ] || put "$G/UDC" ""
    echo "Prepared unbound USB1 SS-only gadget. Requires supplied f_uvc SS-only descriptor patch."
    ;;
run)
    [ -d "$G" ] || fail "run prepare first"
    : "${UDC:?Set exact USB1 UDC name after board identification}"
    [ -z "$(cat "$G/UDC")" ] || fail "already bound"
    [ -w "/sys/class/udc/$UDC/soft_connect" ] || fail "UDC soft_connect unavailable"
    put "$G/UDC" "$UDC"
    put "/sys/class/udc/$UDC/soft_connect" disconnect
    trap 'printf "disconnect\n" > "/sys/class/udc/$UDC/soft_connect"; printf "\n" > "$G/UDC"' EXIT INT TERM
    shift
    "${BROKER:-/usr/bin/sc130_broker}" --soft-connect "/sys/class/udc/$UDC/soft_connect" "$@"
    ;;
stop)
    [ -d "$G" ] || exit 0
    # The run trap can already have unbound this gadget.
    [ -z "$(cat "$G/UDC")" ] || put "$G/UDC" ""
    # Stop bridge before removing its gadget. Default configfs groups are not removed.
    rm -f "$G/configs/c.1/uvc.usb1" "$F/streaming/class/ss/h" "$F/control/class/ss/h"
    for fmt in "$F/streaming/uncompressed/yuy2" "$F/streaming/framebased/h264"; do
        [ -d "$fmt" ] || continue
        rm -f "$F/streaming/header/h/$(basename "$fmt")" "$fmt/color_matching"
        rmdir "$fmt/1280x1024" "$fmt"
    done
    rmdir "$F/streaming/header/h" "$F/control/header/h"
    [ ! -d "$F/streaming/color_matching/yuy2" ] || rmdir "$F/streaming/color_matching/yuy2"
    rmdir "$F" "$G/configs/c.1/strings/0x409" "$G/configs/c.1" "$G/strings/0x409" "$G"
    ;;
*) fail "usage: $0 prepare | run [bridge options] | stop" ;;
esac
