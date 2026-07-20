#!/bin/bash
set -euo pipefail

zerotier-cli listnetworks -j | jq -c '.[] | select(.dns.servers | length > 0)' | while read -r net; do
    iface=$(echo "$net" | jq -r '.portDeviceName')
    domain=$(echo "$net" | jq -r '.dns.domain')
    servers=$(echo "$net" | jq -r '.dns.servers | join(" ")')

    if [ -n "$iface" ] && [ "$iface" != "null" ]; then
        echo "Setting DNS for $iface: servers=[$servers] domain=$domain"
        resolvectl dns "$iface" $servers
        resolvectl domain "$iface" "~$domain"
    fi
done
