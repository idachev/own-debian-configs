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

## WiFi watchdog

Sometimes the office WiFi drops and NetworkManager leaves the WiFi device
`disconnected`. It stops trying after its autoconnect retries
(`connection.autoconnect-retries`, 4 by default) and the laptop stays offline
until someone reconnects by hand.

`wifi-watchdog.sh` reconnects it. A systemd timer runs it every 2 minutes.

### How it works

The script does nothing when:

- WiFi is connected (silent run, nothing logged);
- an ethernet device is connected;
- networking, the WiFi radio or the WiFi hardware switch is disabled;
- the WiFi device is unmanaged, e.g. during suspend/resume;
- WiFi is still connecting (NetworkManager states 40..90);
- no saved autoconnect network is visible in the scan, e.g. on a train.

Otherwise it waits 20 seconds, checks again, and tries these steps in order.
It stops at the first one that connects:

1. `nmcli device connect <iface>` (also bypasses NetworkManager's autoconnect
   block)
2. WiFi radio off/on
3. restart `NetworkManager`
4. reload the WiFi driver (`iwlmvm`/`iwlwifi` on Intel)

Before each step it checks the skip conditions again and stops if one now
holds. Steps 3 and 4 run at most once per 15 minutes. After a reconnect the
script starts `zerotier-dns-fix.service` if it exists, so ZeroTier DNS is
reapplied.

Radio off and driver unload leave a marker in `/run/wifi-watchdog.*`. If the
run is stopped or the undo fails, the exit handler or the next run turns the
radio back on and loads the driver again, so the watchdog never leaves WiFi
worse than it found it.

### Files

| Repo file | Installed to |
|-----------|--------------|
| `wifi-watchdog.sh` | `/usr/local/bin/wifi-watchdog.sh` |
| `wifi-watchdog.service` | `/etc/systemd/system/wifi-watchdog.service` |
| `wifi-watchdog.timer` | `/etc/systemd/system/wifi-watchdog.timer` |

Runtime state in `/run` (cleared on boot): `wifi-watchdog.lock`,
`wifi-watchdog.heavy` (last step 3/4 time), `wifi-watchdog.radio-off`,
`wifi-watchdog.driver-unloaded`.

### Tunables

Set them with `sudo systemctl edit wifi-watchdog.service` as
`Environment=NAME=value` under `[Service]`.

| Variable | Default | Meaning |
|----------|---------|---------|
| `WIFI_WATCHDOG_RETRY_SECS` | `20` | wait before the second check |
| `WIFI_WATCHDOG_WAIT_SECS` | `40` | wait for a connection after each step |
| `WIFI_WATCHDOG_COOLDOWN_SECS` | `900` | minimum time between steps 3/4 |
| `WIFI_WATCHDOG_DRIVER_RELOAD` | `1` | `0` skips step 4 |
| `WIFI_WATCHDOG_FIRST_STEP` | `1` | start at this step, for testing steps 2-4 |

### Install

Run from this directory:

```
sudo cp wifi-watchdog.sh /usr/local/bin/wifi-watchdog.sh
sudo chmod +x /usr/local/bin/wifi-watchdog.sh

sudo cp wifi-watchdog.service /etc/systemd/system/wifi-watchdog.service
sudo cp wifi-watchdog.timer /etc/systemd/system/wifi-watchdog.timer

sudo systemctl daemon-reload
sudo systemctl enable --now wifi-watchdog.timer
```

To update after a change, repeat the `cp` lines and `daemon-reload`.

### Verify

```
systemctl status wifi-watchdog.timer
systemctl list-timers wifi-watchdog.timer
journalctl -u wifi-watchdog -n 50 --no-pager
```

A run while WiFi is connected logs nothing and exits `0/SUCCESS`.

### Test recovery

This drops WiFi for about a minute. Do not run it over a WiFi-only remote
session.

```
nmcli device disconnect wlp147s0
sudo systemctl start wifi-watchdog.service
journalctl -u wifi-watchdog -n 30 --no-pager
```

Expected: `wifi connected via device connect`.

To test a later step, start there. Stop the timer first so a timer run does
not fix WiFi with step 1 in the middle of the test. Example for step 3
(`NetworkManager` restart):

```
sudo systemctl stop wifi-watchdog.timer
nmcli device disconnect wlp147s0
sudo WIFI_WATCHDOG_FIRST_STEP=3 /usr/local/bin/wifi-watchdog.sh
sudo systemctl start wifi-watchdog.timer
```

Expected: `wifi connected via NetworkManager restart`. Steps 3 and 4 then
stay in cooldown for 15 minutes; `sudo rm /run/wifi-watchdog.heavy` clears it.

### Log messages

| Message | Meaning |
|---------|---------|
| `wifi connected via <step>` | recovery worked at that step |
| `no known network in range, skip` | no saved network visible, nothing to do |
| `<iface> activating (state N), skip` | NetworkManager is still connecting |
| `heavy step cooldown active, ...` | steps 1-2 failed, steps 3-4 ran less than 15 minutes ago |
| `... stop recovery` | ethernet, a disabled radio or suspend appeared during recovery |
| `wifi radio still off, retry on next run` | radio restore failed, the next run tries again |
| `wifi still not connected after all steps` | all four steps failed, check `journalctl -u NetworkManager` |
