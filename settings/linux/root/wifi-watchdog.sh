#!/bin/bash
# Reconnect WiFi when NetworkManager leaves it disconnected while a known network is in range.
# Escalate: device connect, radio off/on, NetworkManager restart, driver reload.

set -euo pipefail

RETRY_SECS="${WIFI_WATCHDOG_RETRY_SECS:-20}"
WAIT_SECS="${WIFI_WATCHDOG_WAIT_SECS:-40}"
COOLDOWN_SECS="${WIFI_WATCHDOG_COOLDOWN_SECS:-900}"
DRIVER_RELOAD="${WIFI_WATCHDOG_DRIVER_RELOAD:-1}"
LOCK_FILE=/run/wifi-watchdog.lock
COOLDOWN_FILE=/run/wifi-watchdog.heavy
RADIO_PENDING_FILE=/run/wifi-watchdog.radio-off
DRIVER_PENDING_FILE=/run/wifi-watchdog.driver-unloaded
NM_SERVICE=NetworkManager
DNS_FIX_SERVICE=zerotier-dns-fix.service

log() {
    echo "wifi-watchdog: $*"
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

find_wifi_iface() {
    nmcli -t -f DEVICE,TYPE device 2>/dev/null | awk -F: '$2 == "wifi" { print $1; exit }'
}

# NetworkManager device state number: 10 unmanaged, 20 unavailable, 30 disconnected,
# 40..90 activating, 100 connected.
wifi_state() {
    local iface=$1 state
    state=$(nmcli -g GENERAL.STATE device show "${iface}" 2>/dev/null || true)
    state=${state%% *}
    case "${state}" in
        ''|*[!0-9]*) echo 0 ;;
        *) echo "${state}" ;;
    esac
}

wifi_connected() {
    [ "$(wifi_state "$1")" -eq 100 ]
}

ethernet_connected() {
    nmcli -t -f TYPE,STATE device 2>/dev/null | grep '^ethernet:connected$' >/dev/null
}

wifi_enabled() {
    [ "$(nmcli networking 2>/dev/null || true)" = "enabled" ] &&
        [ "$(nmcli radio wifi 2>/dev/null || true)" = "enabled" ] &&
        [ "$(nmcli -g WIFI-HW general 2>/dev/null || true)" = "enabled" ]
}

known_ssids() {
    local uuid type autoconnect
    nmcli -t -f UUID,TYPE,AUTOCONNECT connection show 2>/dev/null |
        while IFS=: read -r uuid type autoconnect; do
            if [ "${type}" = "802-11-wireless" ] && [ "${autoconnect}" = "yes" ]; then
                nmcli -g 802-11-wireless.ssid connection show "${uuid}" 2>/dev/null || true
            fi
        done | grep -v '^$' | sort -u
}

visible_ssids() {
    local iface=$1
    nmcli -g SSID device wifi list ifname "${iface}" --rescan auto 2>/dev/null |
        grep -v '^$' | sort -u || true
}

known_in_range() {
    local iface=$1 known visible
    known=$(known_ssids)
    visible=$(visible_ssids "${iface}")
    if [ -z "${known}" ] || [ -z "${visible}" ]; then
        return 1
    fi
    comm -12 <(printf '%s\n' "${known}") <(printf '%s\n' "${visible}") | sed -n '1p'
}

wait_connected() {
    local iface=$1 waited=0
    while [ "${waited}" -lt "${WAIT_SECS}" ]; do
        if wifi_connected "${iface}"; then
            return 0
        fi
        sleep 5
        waited=$((waited + 5))
    done
    wifi_connected "${iface}"
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

mark_heavy() {
    date +%s >"${COOLDOWN_FILE}"
}

wifi_driver() {
    local iface=$1 link
    link=$(readlink -f "/sys/class/net/${iface}/device/driver" 2>/dev/null || true)
    if [ -n "${link}" ]; then
        basename "${link}"
    fi
}

step_device_connect() {
    local iface=$1
    log "step 1: nmcli device connect ${iface}"
    timeout $((WAIT_SECS + 10)) nmcli --wait "${WAIT_SECS}" device connect "${iface}" >/dev/null 2>&1 || true
    wait_connected "${iface}"
}

step_radio_cycle() {
    local iface=$1
    log "step 2: wifi radio off/on"
    touch "${RADIO_PENDING_FILE}"
    nmcli radio wifi off || true
    sleep 3
    restore_radio
    wait_connected "${iface}"
}

step_nm_restart() {
    local iface
    log "step 3: restart ${NM_SERVICE}"
    mark_heavy
    timeout 60 systemctl restart "${NM_SERVICE}" || log "${NM_SERVICE} restart failed"
    sleep 10
    iface=$(find_wifi_iface)
    [ -n "${iface}" ] && wait_connected "${iface}"
}

step_driver_reload() {
    local iface=$1 driver
    driver=$(wifi_driver "${iface}")
    if [ "${DRIVER_RELOAD}" != "1" ] || [ -z "${driver}" ]; then
        log "step 4: driver reload disabled or driver unknown, skip"
        return 1
    fi
    log "step 4: reload driver ${driver}"
    mark_heavy
    echo "${driver}" >"${DRIVER_PENDING_FILE}"
    if [ "${driver}" = "iwlwifi" ]; then
        modprobe -r iwlmvm iwlwifi || log "modprobe -r failed"
    else
        modprobe -r "${driver}" || log "modprobe -r failed"
    fi
    sleep 5
    restore_driver
    sleep 10
    iface=$(find_wifi_iface)
    [ -n "${iface}" ] && wait_connected "${iface}"
}

# Radio off and driver unload leave a marker until undone, so an interrupted
# or failed step is repaired on exit or on the next run.
restore_radio() {
    if [ ! -f "${RADIO_PENDING_FILE}" ]; then
        return 0
    fi
    nmcli radio wifi on >/dev/null 2>&1 || true
    if [ "$(nmcli radio wifi 2>/dev/null || true)" = "enabled" ]; then
        rm -f "${RADIO_PENDING_FILE}"
        return 0
    fi
    log "wifi radio still off, retry on next run"
    return 1
}

restore_driver() {
    local driver
    if [ ! -f "${DRIVER_PENDING_FILE}" ]; then
        return 0
    fi
    driver=$(cat "${DRIVER_PENDING_FILE}" 2>/dev/null || true)
    if [ -n "$(find_wifi_iface)" ] || [ -z "${driver}" ]; then
        rm -f "${DRIVER_PENDING_FILE}"
        return 0
    fi
    modprobe "${driver}" || log "modprobe ${driver} failed"
    local waited=0
    while [ "${waited}" -lt 15 ] && [ -z "$(find_wifi_iface)" ]; do
        sleep 1
        waited=$((waited + 1))
    done
    if [ -n "$(find_wifi_iface)" ]; then
        rm -f "${DRIVER_PENDING_FILE}"
        return 0
    fi
    log "wifi device still missing after modprobe ${driver}, retry on next run"
    return 1
}

restore_pending() {
    restore_driver || true
    restore_radio || true
}

# Ethernet up, wifi disabled by someone else, or device unmanaged (suspend):
# stop the recovery before the next step.
still_eligible() {
    local iface=$1
    if ethernet_connected; then
        log "ethernet connected, stop recovery"
        return 1
    fi
    if ! wifi_enabled; then
        log "networking or wifi radio disabled, stop recovery"
        return 1
    fi
    if [ "$(wifi_state "${iface}")" -lt 20 ]; then
        log "${iface} unmanaged, stop recovery"
        return 1
    fi
    return 0
}

recovered() {
    log "wifi connected via $1"
    if systemctl cat "${DNS_FIX_SERVICE}" >/dev/null 2>&1; then
        systemctl start "${DNS_FIX_SERVICE}" >/dev/null 2>&1 || true
    fi
    exit 0
}

main() {
    need_root
    acquire_lock
    trap restore_pending EXIT
    trap 'exit 143' TERM INT

    restore_pending

    local iface state ssid
    iface=$(find_wifi_iface)
    if [ -z "${iface}" ]; then
        log "no wifi device, skip"
        exit 0
    fi

    if wifi_connected "${iface}"; then
        exit 0
    fi

    if ethernet_connected; then
        log "ethernet connected, skip"
        exit 0
    fi

    if ! wifi_enabled; then
        log "networking or wifi radio disabled, skip"
        exit 0
    fi

    state=$(wifi_state "${iface}")
    if [ "${state}" -lt 20 ]; then
        log "${iface} unmanaged (suspend/resume?), skip"
        exit 0
    fi

    log "${iface} not connected (state ${state}), retry in ${RETRY_SECS}s"
    sleep "${RETRY_SECS}"
    if wifi_connected "${iface}"; then
        log "connected after retry"
        exit 0
    fi

    # Act only on unavailable (20) or disconnected (30). Leave an activation
    # in progress (40..90) to NetworkManager.
    state=$(wifi_state "${iface}")
    if [ "${state}" -gt 30 ]; then
        log "${iface} activating (state ${state}), skip"
        exit 0
    fi
    if ! still_eligible "${iface}"; then
        exit 0
    fi

    if ! ssid=$(known_in_range "${iface}") || [ -z "${ssid}" ]; then
        log "no known network in range, skip"
        exit 0
    fi
    log "known network '${ssid}' in range, start recovery"

    if step_device_connect "${iface}"; then
        recovered "device connect"
    fi
    still_eligible "${iface}" || exit 0
    if step_radio_cycle "${iface}"; then
        recovered "radio off/on"
    fi

    if in_cooldown; then
        log "heavy step cooldown active, skip NetworkManager restart and driver reload"
        exit 0
    fi

    still_eligible "${iface}" || exit 0
    if step_nm_restart; then
        recovered "${NM_SERVICE} restart"
    fi
    iface=$(find_wifi_iface)
    if [ -z "${iface}" ]; then
        log "wifi device missing after ${NM_SERVICE} restart"
        exit 1
    fi
    still_eligible "${iface}" || exit 0
    if step_driver_reload "${iface}"; then
        recovered "driver reload"
    fi

    log "wifi still not connected after all steps"
    exit 1
}

main "$@"
