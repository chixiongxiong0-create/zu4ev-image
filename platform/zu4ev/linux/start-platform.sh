#!/bin/sh
# USB setup errors must never gate camera/DP startup.
export USB_VID=0x1d6b USB_PID=0x0102 USB_SERIAL=SC130-PLATFORM-001
[ ! -r /etc/sc130-platform.conf ] || . /etc/sc130-platform.conf
[ ! -r /etc/sc130-nv12.conf ] || . /etc/sc130-nv12.conf
export UVC_FORMAT=${UVC_FORMAT:-h264}
if [ "$UVC_FORMAT" = h264 ]; then
 # The installed U-Boot overrides chosen/bootargs, including maxcpus=1.
 # Enforce the measured CPU0-only configuration before loading video drivers
 # or selecting IRQ affinity. Refuse a silently different H264 configuration.
 for cpu in 3 2 1; do
  online=/sys/devices/system/cpu/cpu$cpu/online
  [ ! -f "$online" ] || printf '0\n' > "$online" || exit 1
 done
 [ "$(cat /sys/devices/system/cpu/online)" = 0 ] || exit 1
 modprobe xlnx_vcu || echo 'VCU clock provider unavailable; inspect dmesg'
 modprobe allegro || echo 'VCU encoder unavailable; capture and DP continue'
fi
insmod /opt/sc130/sc130_capture.ko || echo 'capture module already loaded or probe failed; inspect dmesg'
if [ -f /opt/sc130/sc130_raw.ko ]; then
 insmod /opt/sc130/sc130_raw.ko || echo 'RAW capture module unavailable; inspect dmesg'
fi
set --
if [ "${SC130_USE_NV12:-0}" = 1 ] && [ "$UVC_FORMAT" = h264 ]; then
 insmod /opt/sc130/sc130_nv12.ko || echo 'NV12 capture unavailable; inspect dmesg; CPU fallback is disabled'
 set -- --nv12 /dev/sc130-nv12
fi
soft=
if sh /opt/sc130/setup_uvc.sh prepare; then
 for path in /sys/class/udc/*; do
  [ -d "$path" ] || continue
  udc=${path##*/}
  if [ -w "$path/soft_connect" ]; then
   printf 'disconnect\n' > "$path/soft_connect"
   if printf '%s\n' "$udc" > /sys/kernel/config/usb_gadget/sc130_platform/UDC; then
    printf 'disconnect\n' > "$path/soft_connect"
    soft=$path/soft_connect
   fi
  fi
  break
 done
fi
/opt/sc130/tune-irq.sh &
# No USB presence, STREAMON, or DP connector state is a prerequisite here.
if [ -n "$soft" ]; then
 exec /usr/bin/sc130_platform_bridge --usb-format "$UVC_FORMAT" --soft-connect "$soft" "$@"
else
 exec /usr/bin/sc130_platform_bridge --usb-format "$UVC_FORMAT" "$@"
fi
