# Mac → home Linux via FRA hop (NoMachine + ZeroTier)

**Status:** plan, 5–6 months
**Client:** new Mac, offices / travel
**Host:** old Linux laptop, stays at home
**Hop:** existing Frankfurt VM (public IP)

Daily use is a Mac trackpad controlling the home Linux desktop. The hop exists because the laptop has no public IP and office NAT often blocks UDP hole punching. It is a **network path only**, not a second desktop.

Fill these in when implementing:

| Placeholder | Value |
|---|---|
| `FRA_PUBLIC_IP` | |
| `ZT_NETWORK_ID` | |
| `ZT_CIDR` | overlay subnet from Central (e.g. `10.147.17.0/24`) |
| `LINUX_ZT_IP` | |
| `FRA_SSH_USER` | |

---

## 1. Topology

```
Mac (office NAT, often UDP-hostile)
    │  ZeroTier UDP (DIRECT when the office allows it)
    │  fallback TCP 443 → FRA Pylon
    │  SSH 22 backup
    ▼
FRA VM  (public IP, always on)
    │  Pylon reflect  — TCP 443 + UDP 9993  (not a ZeroTier member)
    │  sshd           — reverse-tunnel endpoint
    ▼
Linux laptop (home NAT, lid closed, always on)
    ZeroTier + NoMachine server  ← physical desktop
```

NoMachine always targets **`LINUX_ZT_IP:4000`** (or `127.0.0.1:4000` only on the SSH backup). Never open a NoMachine session on FRA and hop again.

When office UDP works, Mac ↔ Linux may go **DIRECT** and skip FRA on the data plane. That is a win for trackpad latency. FRA is still required as the TCP-relay and SSH meeting point when DIRECT fails.

---

## 2. Why this stack

| Choice | Why |
|---|---|
| **NoMachine** on Mac + Linux | Best documented Mac→Linux two-finger scroll. Pinch / swipe-back are not forwarded by any tool; Linux does not have those gestures. Version **≥ 9.8.2**, preferably **10.x** (Wayland Chrome scroll fix is 9.8.2). Protocol **NX**, not SSH. Free Personal: one session to the physical display. |
| **ZeroTier** (already in use) | Overlay LAN; both sides connect **outbound**. Carries UDP, so NoMachine multimedia UDP on port 4000 still works **inside** the overlay. Do not add Tailscale on the same machines. |
| **FRA Pylon `reflect` on TCP 443** | Office networks often block UDP. Default ZeroTier fallback is a distant planet (RELAY/TUNNELED, 150–300 ms). Pylon makes that fallback **your** FRA box. A ZeroTier **moon is deprecated** and is not reliably preferred as relay. |
| **FRA is not a ZeroTier member** (default) | Pylon binds **UDP 9993**. `zerotier-one` also binds 9993. Running both on FRA is a port clash. Pylon is not a ZT node; it is a TCP↔UDP relay. Watchdog probes FRA over **TCP 22 or 443**, not a ZT IP. |
| **SSH reverse tunnel as backup** | Last resort when even 443/ZT dies. Official: NX **UDP is disabled** on SSH. Trackpad/video will feel worse. Keep it for “I can work”, not daily. |
| **No double encode** | Mac → FRA desktop → Linux doubles latency and wrecks pointer/scroll. |

Do **not** install: Tailscale, WireGuard hub (unless after a week almost every office is TUNNELED even with Pylon), ZeroTier moon, NoMachine server on FRA, RustDesk/AnyDesk/TeamViewer as the main path.

Optional later: join FRA to ZeroTier with `"primaryPort": 9994` in `local.conf` if you want overlay SSH to the VM. Do **not** leave FRA’s `zerotier-one` on 9993.

Revisit a WireGuard star **only** if real office days still show planet RELAY / non-FRA TUNNELED after Pylon is configured.

---

## 3. The three machines

### 3.1 Mac — client

**Role:** operator. Lives on hostile networks.

| What | Why |
|---|---|
| ZeroTier One, same network as Linux | Overlay IP; no inbound ports at home |
| `local.conf` → `tcpFallbackRelay: FRA_PUBLIC_IP/443`, `forceTcpRelay: false` | UDP blocked → hop FRA:443. `false` keeps DIRECT when the office allows UDP (better scroll) |
| NoMachine **Player** 10.x (min 9.8.2) | Client only. NX, host = `LINUX_ZT_IP`, port 4000, **UDP multimedia on** |
| SSH client + FRA key | VM admin + backup tunnel |
| Do **not** enable NoMachine Network / cloud ID | Second relay you do not control |

**macOS ZeroTier config** (root, then restart the daemon):

`/Library/Application Support/ZeroTier/One/local.conf`

```json
{
  "settings": {
    "tcpFallbackRelay": "FRA_PUBLIC_IP/443",
    "forceTcpRelay": false
  }
}
```

- Slash form `IP/PORT` is required (`1.2.3.4/443`), not `IP:PORT`.
- `allowTcpFallbackRelay` defaults to true; do not set it false.
- Restart: `sudo launchctl kickstart -k system/com.zerotier.one`
- With `forceTcpRelay: false`, ZeroTier can take **a few minutes** to fall over to TCP. Do not assume Pylon is broken in the first 30 seconds on a UDP-hostile network.
- For a one-shot test of Pylon, temporarily set `forceTcpRelay: true`, confirm `zerotier-cli info` shows `TUNNELED` and ping ≈ FRA RTT, then set it back to `false`.

CLI on Mac is often `/usr/local/bin/zerotier-cli` or `/Library/Application\ Support/ZeroTier/One/zerotier-cli` (needs sudo).

**NoMachine connection**

| Field | Value |
|---|---|
| Protocol | NX (not SSH) |
| Host | `LINUX_ZT_IP` (`zerotier-cli listnetworks`) |
| Port | 4000 |
| UDP for multimedia | on |

**Trackpad / input (session menu, Ctrl+Alt+0)**

- Two-finger tap: native first. Enable **Emulate right mouse button** only if secondary click fails.
- **Grab keyboard** only if Linux shortcuts must win. Then disable macOS Mission Control “Move left/right a space”, or Ctrl+arrows never reach Linux.
- Display: adaptive. Raise quality if terminal/IDE text is mushy; do not chase 4K on office Wi‑Fi.
- Do not debug Input until `zerotier-cli peers` for the Linux LEAF is DIRECT or a **short** FRA hop (`TUNNELED` with FRA-like RTT).

**Office habit:** captive portal (browser) first, then ZeroTier. If `info` is `TUNNELED` and scroll is bad **and** ping is 150+ ms, Pylon is not in path — fix FRA/local.conf. If ping is ~FRA and scroll is only “a bit heavy”, use it; SSH backup that day only if it is unusable.

---

### 3.2 FRA VM — hop only

**Role:** public meeting point. Always on, small, **no desktop, no ZeroTier One**.

| What | Why |
|---|---|
| **Pylon `reflect`** | Dumb TCP relay. Clients speak TCP 443; Pylon speaks UDP toward ZeroTier. Not a ZT member. |
| `sshd`, key-only, fail2ban | Admin + backup reverse tunnel |
| Docker | Official Pylon image |
| Do **not** run `zerotier-one` on UDP 9993 | Clashes with Pylon |
| Do **not** run NoMachine server | Double-desktop failure mode |
| Do **not** run a moon | Deprecated; planets still win as relay |

**Public firewall / security group:**

| Port | Proto | Why |
|---|---|---|
| 22 | TCP | SSH admin + backup tunnel |
| 443 | TCP | Pylon reflect (offices allow 443) |
| 9993 | UDP | Pylon’s UDP side (official mapping) |

No 4000 on the public internet.

Pylon `reflect` is a protocol-specific ZeroTier TCP proxy, not SOCKS. It still listens on the public IP. For 5–6 months that is acceptable; you cannot allowlist office egress IPs.

**Pylon** — container listens on **443/tcp** internally. Map the host port onto that:

```bash
docker run --name zt-pylon --restart=always --init \
  -p 443:443 -p 9993:9993/udp \
  zerotier/pylon:latest reflect
```

If host 443 is already used (caddy/nginx):

```bash
docker run --name zt-pylon --restart=always --init \
  -p 8443:443 -p 9993:9993/udp \
  zerotier/pylon:latest reflect
```

Put **`FRA_PUBLIC_IP/8443`** in Mac `tcpFallbackRelay`. Prefer 443 when free.

Official ZeroTier note: **host UFW often fights Docker published ports**. Prefer the cloud security group as the real firewall, or allow 22/443/tcp and 9993/udp in UFW *and* confirm from outside:

```bash
nc -vz FRA_PUBLIC_IP 443
```

If Pylon logs nothing when the Mac is `TUNNELED`, the publish never reached the internet.

---

### 3.3 Home Linux laptop — server

**Role:** the machine you actually use. Must survive lid-closed, no monitor, weeks unattended.

| What | Why |
|---|---|
| ZeroTier One, same network, enabled on boot | Outbound overlay; no home port-forward |
| Do **not** set `forceTcpRelay` here | Home NAT usually punches UDP to FRA/Pylon; forcing TCP would permanently kill NX UDP |
| Same `tcpFallbackRelay` **only if** home ISP blocks UDP (`info` stays `TUNNELED` even on home Wi‑Fi) | Rare; diagnose before copying the Mac config |
| NoMachine **server** 10.x (min 9.8.2), enabled on boot | Physical desktop of the logged-in user |
| Graphical session always logged in | Physical desktop needs a session. Auto-login at home is acceptable for 5–6 months if the house is trusted; otherwise lock the screen, do not suspend |
| Stay-awake (see §5) | Lid / idle suspend is the #1 outage |
| Watchdog → FRA **TCP** 22 or 443 | Cloud VMs often drop ICMP. Ping is not a liveness test |
| `autossh` reverse tunnel to FRA **always on** | Backup is already up when an office kills ZT; cheap |
| X11 session if Wayland + old GPU/DE is flaky | 5–6 months: less pain than debugging Wayland capture |

**Firewall**

Default incoming deny is enough **if** you never `ufw allow 4000` from the world.

Do **not** add a blanket `ufw deny 4000` after an interface allow — rule order can shadow the overlay. Allow from the overlay CIDR instead:

```bash
sudo ufw allow from ZT_CIDR to any port 4000 proto tcp
sudo ufw allow from ZT_CIDR to any port 4000 proto udp
sudo ufw allow 9993/udp comment 'zerotier primary'
```

`zt+` wildcards are **not** reliable in UFW. Confirm the iface with `ip -br l` (`zt…`) only if you write an iface-specific rule.

UDP 9993 inbound on the laptop matters for **DIRECT**. ZeroTier also uses a random secondary UDP port; if home stays RELAY even to FRA, enable UPnP/NAT-PMP on the home router or allow the `zerotier-one` binary through a richer firewall. Do not port-forward 4000 on the home router.

**Unattended:** dedicated NoMachine password. Screen lock is fine; suspend is not.

If the laptop already uses ZeroTier managed DNS, keep `settings/linux/root/zerotier-dns-fix` — unrelated to NoMachine, but Linux otherwise ignores ZT DNS.

---

## 4. Path quality (check this before blaming NoMachine)

On **Mac** and **Linux**:

```bash
sudo zerotier-cli info
sudo zerotier-cli peers
ping -c 20 LINUX_ZT_IP    # from Mac
```

Look at the other machine’s **LEAF** row, not `PLANET`.

| Observation | Meaning | What to do |
|---|---|---|
| `DIRECT` + real IP + low `<lat>` | P2P. Best for trackpad | Leave FRA unused on the data plane |
| `RELAY`, no path IP, ping 150–300 ms | Relaying via a **planet** | `local.conf` / Pylon not in effect, or still in the few-minute fallback window |
| `TUNNELED` on `info`, ping ~40–80 ms | TCP via **your** FRA Pylon | Expected on hostile office Wi‑Fi. Usable |
| `TUNNELED` or `RELAY`, ping 150+ ms | Not FRA | Fix Pylon publish + `tcpFallbackRelay` |
| Ping to `LINUX_ZT_IP` ≈ 20–70 ms, stable | Good enough for NX | Tune NoMachine quality, not the mesh |

Ballpark:

- DIRECT Mac↔home (same city): ~10–30 ms
- Hairpin Mac→FRA Pylon→home: ~40–80 ms — fine for desktop work
- Planet RELAY: 150–300 ms + jitter — unusable scroll

---

## 5. Home laptop stay-alive

This fails more often than ZeroTier.

**logind** — lid must not sleep:

```ini
# /etc/systemd/logind.conf.d/lid.conf
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
```

```bash
sudo systemctl restart systemd-logind
```

Do this while you still have local access.

Also, because DEs ignore logind:

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

Turn off suspend in GNOME/KDE/xfce power settings as well. AC adapter in, battery “never suspend”.

**Lid-closed display:** many laptops drop the internal panel and leave NoMachine at a tiny/black mode. If that happens, a cheap HDMI dummy plug (or a kernel mode like `video=eDP-1:1920x1080D`) is the fix — `HandleLidSwitch=ignore` is not enough.

Other:

- `systemctl set-default graphical.target` if it boots multi-user only
- `systemctl enable --now zerotier-one` and the NoMachine service (`/etc/NX/nxserver --start`; enable the package unit)
- Unattended upgrades: know the reboot window or hold reboots
- Watchdog every 2 minutes: `nc -z FRA_PUBLIC_IP 22` (or 443); restart `zerotier-one` if FRA is up but `zerotier-cli info` is offline; if `/etc/NX/nxserver --status` is dead, restart nxserver

---

## 6. SSH backup (FRA hairpin, NX over TCP only)

Use when ZeroTier from the office is dead. Keep **autossh always running** on the laptop so the FRA loopback is already listening.

FRA `sshd_config`:

```
AllowTcpForwarding yes
GatewayPorts no
ClientAliveInterval 30
ClientAliveCountMax 3
```

`GatewayPorts no` is correct: the reverse tunnel is bound to `127.0.0.1:4000` on FRA, not `0.0.0.0`.

**Linux → FRA** (systemd, key without a prompt — `IdentityFile` + `IdentitiesOnly`):

```bash
autossh -M 0 -N \
  -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
  -o ExitOnForwardFailure=yes \
  -o IdentitiesOnly=yes \
  -i /home/USER/.ssh/id_ed25519 \
  -R 127.0.0.1:4000:127.0.0.1:4000 \
  FRA_SSH_USER@FRA_PUBLIC_IP
```

`nxserver` must accept **localhost:4000** (default `nxd` on `0.0.0.0` does). Loopback is not filtered by UFW.

**Mac, that office day:**

```bash
ssh -N -L 4000:127.0.0.1:4000 FRA_SSH_USER@FRA_PUBLIC_IP
```

NoMachine → `127.0.0.1:4000`, protocol NX. UDP multimedia will not work. Expect heavier scroll.

Do not run a second NoMachine connection definition against FRA’s public IP:4000 — that port must stay loopback-only.

---

## 7. MTU

ZeroTier default MTU is **2800** and fragments on the real path. If DIRECT/FRA RTT is fine but the picture drops or scroll stutters, set the **network** MTU in ZeroTier Central to **1400**, then **leave and rejoin on Mac and Linux** (FRA is not on the network). The Central UI may still display 2800 after a successful change.

---

## 8. Order of work

Do this while you still have physical access to the laptop.

1. **Linux:** stay-awake + mask sleep, graphical login, dummy plug if lid-closed blanks the display, ZeroTier + NoMachine as services, UFW from `ZT_CIDR` to 4000 + UDP 9993, watchdog, autossh unit enabled.
2. **FRA:** Pylon on 443, **no** `zerotier-one`, SSH keys, fail2ban, cloud firewall 22/443/tcp + 9993/udp. Confirm `nc` to 443 from outside.
3. **Mac:** ZeroTier, `local.conf` fallback to FRA, restart daemon, NoMachine player → `LINUX_ZT_IP`.
4. **Test at home Wi‑Fi:** Linux LEAF should be `DIRECT` (or low ping). Two-finger scroll in browser, IDE, terminal. Two-finger tap = right click.
5. **Force-test Pylon** (temporary `forceTcpRelay: true` on Mac): `info` = `TUNNELED`, ping ≈ FRA, Pylon logs traffic. Then set `false` again.
6. **Phone hotspot** (closer to office NAT): if not DIRECT, must look like FRA RTT, not transatlantic.
7. **First real office day:** captive portal → ZT → NX. If TUNNELED and painful with FRA-like ping, SSH backup. Do not install a second mesh.

---

## 9. Done criteria

- From home: session usable with Mac trackpad (smooth two-finger scroll, reliable right-click).
- From a restrictive network: FRA-short `TUNNELED` **or** SSH backup reaches the same Linux desktop.
- Laptop reboot: ZeroTier + NoMachine + session + autossh come back without walking to the machine.
- Lid closed overnight: still reachable the next morning, display not 640×480 unless you chose that.
- FRA reboot: Pylon and `sshd` come back (`--restart=always`). Laptop watchdog sees TCP 22/443 again.

---

## 10. After 5–6 months

Tear down: disable autossh, `docker rm -f zt-pylon`, leave ZeroTier if unused, stop `nxserver` (or uninstall). FRA firewall: drop 443 and 9993 if nothing else needs them. Unmask sleep targets on the laptop.

If the laptop stays a long-term host, revisit: X11 vs Wayland, a small always-on mini PC vs the laptop, and whether a WireGuard star is justified.

---

## 11. Quick command map

| Where | Command |
|---|---|
| Mac / Linux ZT | `sudo zerotier-cli info` · `sudo zerotier-cli peers` · `sudo zerotier-cli listnetworks` |
| Linux NX | `sudo /etc/NX/nxserver --status` · `sudo /etc/NX/nxserver --restart` |
| FRA Pylon | `docker ps` · `docker logs -f zt-pylon` |
| FRA publish check | `nc -vz FRA_PUBLIC_IP 443` |
| Mac fallback | `/Library/Application Support/ZeroTier/One/local.conf` |
| Mac ZT restart | `sudo launchctl kickstart -k system/com.zerotier.one` |
| Linux fallback (usually unset) | `/var/lib/zerotier-one/local.conf` |
| Linux ZT restart | `sudo systemctl restart zerotier-one` |
