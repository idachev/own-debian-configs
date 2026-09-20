#!/bin/bash
# Probe OPNsense over the ZeroTier overlay. Restart zerotier-one if the probe fails.
# Bind ping to the 172.22.172.0/24 iface so office LAN cannot fake success.

set -euo pipefail

TARGET="${ZT_WATCHDOG_TARGET:-172.22.172.2}"
MIN_UP_SECS="${ZT_WATCHDOG_MIN_UP_SECS:-120}"
RETRY_SECS="${ZT_WATCHDOG_RETRY_SECS:-20}"
COOLDOWN_SECS="${ZT_WATCHDOG_COOLDOWN_SECS:-900}"
PING_COUNT="${ZT_WATCHDOG_PING_COUNT:-3}"
PING_WAIT="${ZT_WATCHDOG_PING_WAIT:-3}"
RESTART_TIMEOUT_SECS="${ZT_WATCHDOG_RESTART_TIMEOUT_SECS:-60}"
LOCK_FILE=/run/zerotier-watchdog.lock
COOLDOWN_FILE=/run/zerotier-watchdog.restart
ZT_SERVICE=zerotier-one
DNS_FIX_SERVICE=zerotier-dns-fix.service

log() {
    echo "zerotier-watchdog: $*"
}

need_root() {
    if [ "${EUID}" -ne 0 ]; then
        log "must run as root"
        exit 1
    fi
}

acquire_lock() {
    exec 9>"${LOCK_FILE}"
    if ! flock -n 9; then
        log "already running, skip"
        exit 0
    fi
}

find_zt_iface() {
    ip -4 -o addr show | awk '$4 ~ /^172\.22\.172\./ { print $2; exit }'
}

has_zt_membership() {
    local f
    for f in /var/lib/zerotier-one/networks.d/*.conf; do
        case "${f}" in
            *.local.conf) continue ;;
        esac
        if [ -f "${f}" ]; then
            return 0
        fi
    done
    return 1
}

probe() {
    local iface=$1
    ping -n -c "${PING_COUNT}" -W "${PING_WAIT}" -I "${iface}" "${TARGET}" >/dev/null 2>&1
}

zt_uptime_secs() {
    local pid
    pid=$(systemctl show -p MainPID --value "${ZT_SERVICE}" 2>/dev/null || true)
    if [ -z "${pid}" ] || [ "${pid}" = "0" ]; then
        echo 0
        return
    fi
    ps -o etimes= -p "${pid}" 2>/dev/null | awk '{ s=$1+0 } END { print s+0 }'
}

in_cooldown() {
    local last now
    if [ ! -f "${COOLDOWN_FILE}" ]; then
        return 1
    fi
    last=$(cat "${COOLDOWN_FILE}" 2>/dev/null || echo 0)
    case "${last}" in
        ''|*[!0-9]*) last=0 ;;
    esac
    now=$(date +%s)
    if [ $((now - last)) -lt "${COOLDOWN_SECS}" ]; then
        return 0
    fi
    return 1
}

mark_restart() {
    date +%s >"${COOLDOWN_FILE}"
}

overlay_ok() {
    local iface
    iface=$(find_zt_iface)
    if [ -z "${iface}" ]; then
        return 1
    fi
    probe "${iface}"
}

restart_zerotier() {
    log "restarting ${ZT_SERVICE}"
    if ! timeout "${RESTART_TIMEOUT_SECS}" systemctl restart "${ZT_SERVICE}"; then
        log "restart timed out after ${RESTART_TIMEOUT_SECS}s"
        return 1
    fi
    mark_restart
    systemctl start "${DNS_FIX_SERVICE}" >/dev/null 2>&1 || true
    sleep "${RETRY_SECS}"
    if overlay_ok; then
        log "probe ok after restart via $(find_zt_iface) -> ${TARGET}"
        return 0
    fi
    log "probe still failing after restart"
    return 1
}

main() {
    need_root
    acquire_lock

    if [ "$(systemctl is-enabled "${ZT_SERVICE}" 2>/dev/null || true)" != "enabled" ]; then
        log "${ZT_SERVICE} is not enabled, skip"
        exit 0
    fi

    if ! has_zt_membership; then
        log "no ZeroTier network membership, skip"
        exit 0
    fi

    local iface
    iface=$(find_zt_iface)
    if overlay_ok; then
        log "probe ok via ${iface} -> ${TARGET}"
        exit 0
    fi

    log "probe failed via ${iface:-none} -> ${TARGET}, retry in ${RETRY_SECS}s"
    sleep "${RETRY_SECS}"
    iface=$(find_zt_iface)
    if overlay_ok; then
        log "probe ok after retry via ${iface} -> ${TARGET}"
        exit 0
    fi

    local up
    up=$(zt_uptime_secs)
    if [ "${up}" -gt 0 ] && [ "${up}" -lt "${MIN_UP_SECS}" ]; then
        log "${ZT_SERVICE} started ${up}s ago, wait for overlay before restart"
        exit 0
    fi

    if in_cooldown; then
        log "restart cooldown active, skip"
        exit 0
    fi

    restart_zerotier
}

main "$@"
