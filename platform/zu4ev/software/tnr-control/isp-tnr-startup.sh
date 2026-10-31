#!/bin/sh
# Runs in the background after platform startup; never delays the console.
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
bus_ready=0
fail() {
    echo "ISP_TNR_STARTUP_FAILED: $*"
    if [ "$bus_ready" = 1 ]; then
        tnrctl bypass || echo 'Best-effort TNR bypass failed'
    fi
    exit 1
}
trap 'fail "interrupted"' HUP INT TERM
n=0
while ! grep -q '^stats ' /tmp/sc130-platform.log 2>/dev/null; do
    [ "$n" -lt 30 ] || fail 'platform stats not observed within 30 seconds; MMIO untouched'
    sleep 1
    n=$((n + 1))
done
bus_ready=1
n=0
while :; do
    status=$(tnrctl status) || fail 'cannot read TNR status'
    case "$status" in
        *'calibrated=1 '*) break ;;
    esac
    [ "$n" -lt 10 ] || fail 'DDR calibration not observed within 10 seconds'
    sleep 1
    n=$((n + 1))
done
tnrctl bypass || fail 'cannot disable TNR'
tnrctl memtest || fail 'reserved 1MiB DDR memory test failed'
ispctl curve-load /etc/isp/indoor-bright.txt || fail 'cannot load accepted indoor-bright curve'
ispctl set mode ltm || fail 'cannot set LTM mode'
ispctl set black 52 || fail 'cannot set black level'
ispctl set gain 96 || fail 'cannot set gain'
ispctl set sigma 64 || fail 'cannot set sigma'
ispctl apply --swap || fail 'cannot apply LTM profile'
tnrctl set alpha 192 || fail 'cannot set TNR alpha'
tnrctl set motion-low 6 || fail 'cannot set TNR low threshold'
tnrctl set motion-high 20 || fail 'cannot set TNR high threshold'
tnrctl enable || fail 'cannot enable TNR'
sleep 1
status=$(tnrctl status) || fail 'cannot read final TNR status'
printf '%s\n' "$status"
case "$status" in
    *'calibrated=1 history_valid=1 '*) ;;
    *) fail 'final DDR calibration/history state is not valid' ;;
esac
ispctl status || fail 'cannot read final ISP status'
echo ISP_TNR_STARTUP_OK
