#!/bin/sh
# Single boot coordinator. The PS profile must exit before Ibex is authorized.
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
fail() {
    echo "IBEX_STARTUP_FAILED: $*"
    exit 1
}
trap 'fail "interrupted; inspect ownership before starting any PS writer"' HUP INT TERM
/opt/sc130/start-platform.sh >/tmp/sc130-platform.log 2>&1 &
bridge_pid=$!
echo "IBEX_STARTUP bridge_pid=$bridge_pid"
if ! /opt/sc130/isp-tnr-startup.sh >/tmp/isp-tnr-startup.log 2>&1; then
    fail 'PS ISP/TNR initialization failed; no Ibex start attempted; see /tmp/isp-tnr-startup.log'
fi
kill -0 "$bridge_pid" 2>/dev/null || fail 'bridge exited before handoff; see /tmp/sc130-platform.log'
/usr/bin/ibex_iic_prepare --boot-before-handoff || fail 'IIC preparation failed; no Ibex start attempted'
# The packaged boot image has no R5 partition. The only PS ISP configuration
# process launched by /init has now exited. Handoff performs its own commit,
# IIC clock/reset/idle and firmware-ready guards; do not bypass those guards.
if ! /usr/bin/ibex_isp_handoff start --ps-writers-stopped; then
    echo 'IBEX_STARTUP handoff failed; requesting bounded quiescent stop/reclaim'
    if ! /usr/bin/ibex_isp_handoff stop; then
        echo 'IBEX_STOP_INCOMPLETE: keep every PS/R5 writer stopped; ownership was not forced'
    fi
    /usr/bin/ibex_isp_handoff status || :
    fail 'Ibex start failed; no automatic retry'
fi
/usr/bin/ibex_isp_handoff status || fail 'cannot read post-handoff status'
echo 'IBEX_STARTUP_OK: PS profile completed; Ibex owns ISP/sensor; R5 not booted'
