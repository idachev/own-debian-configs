# Root Settings

Files here are linked into `/root` via `create_links`, see the top-level README
`Setup root home dir` section.

## ZeroTier DNS Fix

The ZeroTier Linux client does not apply the DNS servers/search domain pushed by
a network controller (`allowDNS`/managed DNS) - it logs a warning and drops it:

```
WARNING: ignoring call to LinuxEthernetTap::setDns on Linux. This is not implemented yet.
```

See https://github.com/zerotier/ZeroTierOne/issues/2492

`zerotier-dns-fix.sh` works around this by reading `zerotier-cli listnetworks -j`
and pushing each network's `dns.servers`/`dns.domain` to `systemd-resolved` via
`resolvectl` for the matching ZeroTier interface. `zerotier-dns-fix.path` watches
`/var/lib/zerotier-one/networks.d` and triggers `zerotier-dns-fix.service`
whenever ZeroTier rewrites a network's config (join, reconnect, or a controller
side DNS change), so it self-heals without a reboot.

### Install

Requires `jq`: `sudo apt install jq`

```
sudo cp zerotier-dns-fix.sh /usr/local/bin/zerotier-dns-fix.sh
sudo chmod +x /usr/local/bin/zerotier-dns-fix.sh

sudo cp zerotier-dns-fix.service /etc/systemd/system/zerotier-dns-fix.service
sudo cp zerotier-dns-fix.path /etc/systemd/system/zerotier-dns-fix.path

sudo systemctl daemon-reload
sudo systemctl enable --now zerotier-dns-fix.path

# apply immediately instead of waiting for the next network config change
sudo systemctl start zerotier-dns-fix.service
```

### Verify

```
resolvectl status <zerotier-interface>
```

Should show the network's DNS servers and `~<domain>` under that link.

## ZeroTier watchdog

`zerotier-watchdog.sh` pings the OPNsense ZeroTier address `172.22.172.2`
through the local `172.22.172.0/24` interface. The ping is bound to that
interface so office LAN cannot look like overlay success.

A systemd timer runs it every 15 minutes. If two probes 20 seconds apart
both fail, and `zerotier-one` is enabled, has a network membership, has
been up at least 2 minutes, and was not restarted in the last 15 minutes,
the script restarts `zerotier-one` and then starts `zerotier-dns-fix.service`
so managed DNS is reapplied.

### Install

Run from this directory:

```
sudo cp zerotier-watchdog.sh /usr/local/bin/zerotier-watchdog.sh
sudo chmod +x /usr/local/bin/zerotier-watchdog.sh

sudo cp zerotier-watchdog.service /etc/systemd/system/zerotier-watchdog.service
sudo cp zerotier-watchdog.timer /etc/systemd/system/zerotier-watchdog.timer

sudo systemctl daemon-reload
sudo systemctl enable --now zerotier-watchdog.timer
sudo systemctl start zerotier-watchdog.service
```

The last line runs one probe now instead of waiting for the next 15-minute
tick.

### Verify

```
systemctl status zerotier-watchdog.timer
systemctl status zerotier-watchdog.service
journalctl -u zerotier-watchdog -n 50 --no-pager
```

A healthy run logs `probe ok via <iface> -> 172.22.172.2`.
