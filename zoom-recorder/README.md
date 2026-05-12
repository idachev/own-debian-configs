# Zoom Recorder VM (AWS EC2)

A reproducible setup for a cloud Linux VM that joins Zoom meetings (passive
observer), auto-records screen + audio with heavy compression for slide-heavy
content, and can be driven from a phone via VNC.

## What's in this folder

```
zoom-recorder/
├── README.md                                       # this file
├── setup-vm.sh                                     # one-shot setup — run ON the VM
├── local-tunnel.sh                                 # run on the LAPTOP: open/close VNC SSH tunnel
└── vm-files/                                       # source-of-truth for runtime files
    ├── zoom-record-start.sh                        # → ~/bin/ on the VM
    ├── zoom-record-stop.sh                         # → ~/bin/ on the VM
    ├── zoom-recorder-monitor.sh                    # → ~/bin/ (background auto-recorder)
    ├── zoom-recorder-monitor-toggle.sh             # → ~/bin/ (pause/resume monitor)
    ├── record-ad-hoc.sh                            # → ~/bin/ (terminal-only flow)
    ├── zoom-record-start.desktop                   # → ~/Desktop/ launcher
    ├── zoom-record-stop.desktop                    # → ~/Desktop/ launcher
    ├── zoom-recorder-monitor-toggle.desktop        # → ~/Desktop/ launcher
    ├── zoom-recorder-monitor.autostart.desktop     # → ~/.config/autostart/ (XFCE)
    └── vncserver@.service                          # → ~/.config/systemd/user/ (boot-time auto-start)
```

`setup-vm.sh` is idempotent — safe to re-run while iterating.

---

## Quick start: provision a fresh VM

### 1. Launch an EC2 instance

| Setting        | Value                                                       |
| -------------- | ----------------------------------------------------------- |
| AMI            | **Ubuntu Server 24.04 LTS** or 26.04 LTS                    |
| Architecture   | **x86_64** (Zoom Linux client is amd64-only)                |
| Instance type  | **t3.medium** (2 vCPU, 4 GB RAM)                            |
| Storage        | 30 GB **gp3** EBS                                           |
| Security group | inbound **SSH 22 from your IP only**                        |
| Region         | nearest you                                                 |

SSH user is `ubuntu`. Stop the instance between sessions — you only pay EBS
(~$2.40/mo for 30 GB) when stopped.

### 2. Copy this folder to the VM and run setup

```bash
rsync -avz --delete \
  ~/bin/zoom-recorder/ \
  ubuntu@<vm-host>:~/zoom-recorder/

ssh ubuntu@<vm-host>
cd ~/zoom-recorder
./setup-vm.sh
```

The script does, in order:

1. apt-update + install base packages (XFCE, TigerVNC, PulseAudio, ffmpeg,
   wmctrl, xdotool, x11-utils)
2. Configure TigerVNC — random password, **geometry 1920x1080**,
   `AcceptSetDesktopSize=0` (so viewer-side resize won't change the recording
   resolution)
3. Start `vncserver :1` and register it as a **systemd `--user` service** with
   user `linger` enabled, so it comes back automatically after a VM reboot
4. Set up PulseAudio + `zoom_sink` null sink (idempotent across X restarts)
5. Install the Zoom Linux client
6. Install Tailscale (you still need `sudo tailscale up --qr` to authenticate)
7. Install runtime scripts to `~/bin/` and launchers to `~/Desktop/`
8. Register the auto-record monitor in `~/.config/autostart/`

At the end it prints the VNC password and Tailscale IP (if available).

### 3. Authenticate Tailscale (one-time, interactive)

```bash
sudo tailscale up --qr
```

Open the printed URL or scan the QR with your phone.

### 4. Connect via VNC

| Path                      | Address                       | How                                                  |
| ------------------------- | ----------------------------- | ---------------------------------------------------- |
| Laptop+SSH                | `localhost:5901`              | `./local-tunnel.sh start` then VNC viewer            |
| Laptop direct (Tailscale) | `<vm-tailscale-ip>:5901`      | VNC viewer; needs Tailscale on laptop too            |
| Android                   | `<vm-tailscale-ip>:5901`      | Tailscale app + RealVNC Viewer                       |

The SSH-tunnel helper `local-tunnel.sh` (laptop side):

```bash
./local-tunnel.sh start    # open backgrounded tunnel (5901 → VM 5901)
./local-tunnel.sh status   # show state (UP backgrounded / UP foreign / DOWN)
./local-tunnel.sh stop     # kill the backgrounded tunnel

# Overrides
ZOOM_VM_HOST=other-alias  ./local-tunnel.sh start
ZOOM_VNC_PORT=5902        ./local-tunnel.sh start
```

It won't double-bind if port 5901 is already held by something else (e.g.
an interactive `ssh <vm>` session with `LocalForward`).

---

## Setup script knobs (env vars)

```bash
VNC_PASSWORD=changeme  ./setup-vm.sh   # explicit password instead of random
VNC_GEOMETRY=2560x1440 ./setup-vm.sh   # bigger framebuffer (more CPU on encode)
BIND_LOCALHOST_ONLY=yes ./setup-vm.sh  # VNC only on lo (no Tailscale access)
ENABLE_TAILSCALE=no    ./setup-vm.sh   # skip Tailscale install
ENABLE_ZOOM=no         ./setup-vm.sh   # skip Zoom (already installed?)
ENABLE_DESKTOP_ICONS=no ./setup-vm.sh  # skip Desktop launchers
```

---

## Architecture

```
   ┌────────────────────────────────────────────────────────────────┐
   │                       EC2 VM (Ubuntu)                          │
   │                                                                │
   │  Xvnc :1 (1920x1080)  ──────────┐                              │
   │   ▲                              │                             │
   │   │ XFCE autostart               │ audio (output)              │
   │   ▼                              ▼                             │
   │  monitor.sh ── detects ── Zoom ──► pa-sink "zoom_sink"         │
   │   │  (every 5s)            │           │                       │
   │   │  ✓ wmctrl titles       │           ▼                       │
   │   │  ✓ pactl sink-inputs   │      zoom_sink.monitor            │
   │   │  ✓ cpthost process     │           │                       │
   │   ▼                        ▼           ▼                       │
   │  start.sh ───► ffmpeg ◄────────────────┘                       │
   │                  ├── -f x11grab -i :1.0  (video)               │
   │                  ├── -f pulse  -i zoom_sink.monitor (audio)    │
   │                  └── libx264 / AAC ────► ~/recordings/*.mp4    │
   │                                                                │
   │   ~/Desktop:  Start │ Stop │ Auto-Record Toggle                │
   └────────────────────────────────────────────────────────────────┘
            ▲                    ▲
            │ VNC 5901           │ SSH 22
            │                    │
      ┌─────┴────────────┐  ┌────┴───────┐
      │ Android +         │ │ Laptop +    │
      │ Tailscale +       │ │ ssh/VNC     │
      │ RealVNC           │ │ viewer      │
      └───────────────────┘ └─────────────┘
```

Key tricks:

- **No real audio hardware** → PulseAudio null sink lets Zoom "play" audio
  that ffmpeg can capture via the sink's monitor source.
- **No real display** → Xvnc provides a virtual X server at a fixed 1920x1080;
  `AcceptSetDesktopSize=0` rejects viewer-initiated resize requests.
- **Auto-detect framebuffer size** → recording scripts call `xdpyinfo` so a
  geometry change requires no script edits.
- **Per-user PulseAudio daemon** → survives Xvnc restarts; xstartup re-loads
  the null sink only if missing.

---

## Daily workflow

The auto-record monitor is the default path — you usually don't touch the
icons.

1. Start the EC2 instance (AWS console or `aws ec2 start-instances ...`)
2. Connect to VNC (laptop SSH-tunnel, or Tailscale + RealVNC on phone)
3. In Zoom: **Join** meeting — muted, camera off, **Speaker = ZoomSink**
4. Within ~5 s the monitor detects the meeting and starts a recording.
   A "Started: recording-YYYYMMDD-HHMMSS.mp4" toast appears in the VNC
   desktop notifications.
5. When the meeting ends, double-click **Stop Recording**. (Or: leave the
   meeting first, then click Stop.) Stop toast shows part count + total size.
6. Recordings are split into 15-minute parts inside `~/recordings/` — all
   files for one session share a base timestamp:
   ```
   recording-20260511-100000-part000.mp4   # 0 – 15 min
   recording-20260511-100000-part001.mp4   # 15 – 30 min
   recording-20260511-100000-part002.mp4   # 30 – 45 min  (may be short if you stopped)
   ```
   Pull them all down with:
   ```bash
   scp '<vm>:~/recordings/recording-20260511-100000-part*.mp4' ./
   ```
7. Stop the EC2 instance to stop paying compute:
   ```bash
   aws ec2 stop-instances --instance-ids <i-...>
   ```

### Auto-Record Monitor

A background script (`~/bin/zoom-recorder-monitor.sh`) started by XFCE
autostart, ticks every 5 s and looks for an in-progress Zoom meeting using
three independent signals — any one of them is enough:

| Signal | What it checks                                           |
| ------ | -------------------------------------------------------- |
| 1      | `wmctrl -l` window titles matching `Zoom Meeting` / `Zoom Workplace` / `zoom_linux_float_video_window` / `as_toolbar` |
| 2      | `pactl list sink-inputs` showing a stream from `zoom` / `ZOOM VoiceEngine` |
| 3      | `pgrep -f /opt/zoom/cpthost` — Zoom's in-meeting helper  |

Behavior:

- If **in meeting + not recording** → starts a new recording (idempotent).
- If **in meeting + recording crashed** → starts a fresh file with a new
  timestamp on the next tick.
- It does **not** auto-stop on meeting end. You press Stop when done.
- A paused state (toggle icon) makes the monitor a no-op without killing it.

### Three desktop icons

| Icon                 | Behavior                                                              |
| -------------------- | --------------------------------------------------------------------- |
| **Start Recording**  | If no recording → start one. If already recording → notify "already". |
| **Stop Recording**   | `SIGINT` to ffmpeg so mp4 trailer is written; toasts saved size.      |
| **Auto-Record Toggle** | Touches `~/recordings/.monitor.paused` — toggles the monitor on/off. |

Manual override pattern: to genuinely stop mid-meeting (otherwise the monitor
auto-restarts), Toggle **OFF** first, then Stop.

### Recording segmentation (crash safety)

Every recording is split into **15-minute parts** (`-part000.mp4`,
`-part001.mp4`, …) via ffmpeg's `-f segment` muxer. Each part is finalized
with `+faststart` and is independently playable as soon as the next segment
starts. Consequences:

- If the VM crashes / loses power / OOMs mid-recording, you lose at most the
  last partial segment — earlier parts are fully written.
- If the monitor auto-restarts ffmpeg after a death, it gets a new base
  timestamp and starts again at `part000` — easy to tell the sessions apart.

Override the chunk length via env var:

```bash
ZOOM_SEGMENT_SECONDS=600 ~/bin/zoom-record-start.sh    # 10 min
ZOOM_SEGMENT_SECONDS=1800 ~/bin/zoom-record-start.sh   # 30 min
```

Set permanently by adding to `~/.bashrc` (or by editing the XFCE autostart
entry / the start script directly).

---

## Monitoring via SSH

The whole system has plain-text breadcrumbs. Useful one-liners:

### State right now

```bash
ssh <vm> '
echo "monitor:    $(pgrep -af zoom-recorder-monitor.sh | head -1 || echo "(not running)")"
echo "recording:  $(pgrep -af "^ffmpeg .*x11grab" | head -1 || echo "(not running)")"
echo "monitor paused?  $([ -f ~/recordings/.monitor.paused ] && echo YES || echo no)"
echo "in zoom meeting? $(wmctrl -l 2>/dev/null | grep -iqE "zoom meeting|zoom_linux_float|as_toolbar" && echo YES || echo no)"
echo "display:    $(DISPLAY=:1 xdpyinfo 2>/dev/null | awk "/dimensions:/{print \$2}")"
echo "free disk:  $(df -h ~/recordings | awk "NR==2{print \$4}") on $(df -h ~/recordings | awk "NR==2{print \$1}")"
'
```

### Post-reboot health check

After a VM reboot, run this to confirm the whole stack came back cleanly:

```bash
ssh <vm> '
echo "uptime    : $(uptime -p)"
echo "vncserver : $(systemctl --user is-active vncserver@:1) (NRestarts=$(systemctl --user show -p NRestarts --value vncserver@:1))"
echo "Xvnc      : $(pgrep -af Xtigervnc | grep -v grep | head -1 | cut -c1-90)"
echo "monitor   : $(pgrep -af zoom-recorder-monitor.sh | grep -v grep | head -1 | cut -c1-80 || echo NONE)"
echo "env       : $(systemctl --user show-environment | grep ZOOM_REC_REMOTE)"
echo "tailscale : $(sudo tailscale ip -4 2>/dev/null)"
echo "rclone    : $(rclone listremotes 2>/dev/null)"
echo "5901      : $(ss -tln | grep 5901 | head -1)"
echo "sinks     : $(pactl list short sinks | grep -c zoom_sink) zoom_sink module(s)"
'
```

Want to see:

- `NRestarts=0` (the unit didn't fall into a restart loop)
- `monitor` shows a running PID (not `NONE`)
- `env` shows `ZOOM_REC_REMOTE=…` if rclone upload is configured
- `sinks` shows `1 zoom_sink module(s)` (idempotent xstartup is doing its job)

### Tail the monitor log live

```bash
ssh <vm> 'tail -f ~/recordings/.monitor.log'
```

Sample entries:

```
[2026-05-11 12:05:09] monitor started, tick=5s, pid=27215
[2026-05-11 12:05:19] Zoom meeting detected and no recording running — starting
```

### Tail the active ffmpeg log

```bash
ssh <vm> 'ls -t ~/recordings/.recording-*.log | head -1 | xargs tail -f'
```

(`.recording-…log` per file; ffmpeg writes warnings and progress here.)

### List recordings with sizes

```bash
ssh <vm> 'ls -lh ~/recordings/*.mp4 | sort -k9'
```

### Group recordings by session (base timestamp)

```bash
ssh <vm> '
for base in $(ls ~/recordings/recording-*-part000.mp4 2>/dev/null | sed -E "s/-part000.mp4$//" | xargs -n1 basename); do
  total=$(du -ch ~/recordings/${base}-part*.mp4 2>/dev/null | tail -1 | cut -f1)
  parts=$(ls ~/recordings/${base}-part*.mp4 2>/dev/null | wc -l)
  echo "$base  ${parts} parts  ${total}"
done
'
```

### Probe a finished file

```bash
ssh <vm> 'ffprobe -v error -show_format -show_streams \
  ~/recordings/recording-YYYYMMDD-HHMMSS.mp4 2>&1 \
  | grep -E "codec_name|width|height|duration|bit_rate|size"'
```

### Drive the recorder from CLI (no VNC needed)

```bash
ssh <vm> 'DISPLAY=:1 ~/bin/zoom-record-start.sh'    # idempotent start
ssh <vm> 'DISPLAY=:1 ~/bin/zoom-record-stop.sh'     # graceful stop
ssh <vm> 'DISPLAY=:1 ~/bin/zoom-recorder-monitor-toggle.sh'  # pause/resume monitor
```

### Restart the monitor (e.g. after editing the script)

```bash
ssh <vm> '
pkill -f zoom-recorder-monitor.sh 2>/dev/null
rm -f ~/recordings/.monitor.pid
sleep 1
DISPLAY=:1 setsid nohup ~/bin/zoom-recorder-monitor.sh </dev/null >/dev/null 2>&1 &
disown
sleep 1
pgrep -af zoom-recorder-monitor.sh
'
```

### Restart Xvnc (applies geometry / AcceptSetDesktopSize changes — kills Zoom)

```bash
# Preferred (via systemd):
ssh <vm> 'systemctl --user restart vncserver@:1'

# Or direct:
ssh <vm> 'vncserver -kill :1 && vncserver :1'
```

### Check the boot-time service

```bash
ssh <vm> '
  systemctl --user is-enabled vncserver@:1
  systemctl --user status vncserver@:1 --no-pager | head -20
  loginctl show-user "$USER" | grep Linger
'
```

### Pull every new recording then delete on remote

```bash
rsync -avz --remove-source-files <vm>:~/recordings/*.mp4 ./local-zoom/
```

### Clean up old recordings (older than 14 days)

```bash
ssh <vm> 'find ~/recordings -name "recording-*.mp4" -mtime +14 -delete'
```

---

## Ad-hoc recording (no icon, no monitor)

`~/bin/record-ad-hoc.sh [name]` records in the foreground, Ctrl-C to stop.
Useful when you're SSH'd in anyway and don't want the auto-monitor to inject
a parallel recording. Toggle the monitor OFF first if it might race you.

---

## Optional: auto-upload to Google Drive / Dropbox / S3

`zoom-record-stop.sh` has rclone upload baked in. When set, each Stop
uploads every `<base>-partNNN.mp4` of the session to
`$ZOOM_REC_REMOTE/<base>/` and toasts the result. Log lives at
`~/recordings/.upload-<base>.log` for post-mortem.

### 1. Install rclone — **use the .deb, not the snap**

Ubuntu 26.04's apt rclone is 1.60 (4 years old), and the **snap** rclone
breaks our use case: snap's launcher tries to create a transient systemd
scope via dbus, which fails when invoked from an xfce4-session-spawned
.desktop launcher (you'd see `Activated service 'org.freedesktop.systemd1'
failed: Process org.freedesktop.systemd1 exited with status 1` in the
journal and "Upload to … failed" with no rclone log). Grab the current
.deb directly from rclone.org:

```bash
cd /tmp
wget https://downloads.rclone.org/rclone-current-linux-amd64.deb
sudo apt install -y ./rclone-current-linux-amd64.deb
rclone version    # expect 1.74+
```

### 2. Configure a remote

```bash
rclone config        # 'n' new, name 'gdrive', backend 'drive', scope 3 (drive.file)
```

If you don't have a browser on the VM: pick `Use auto config? = n`, run
`rclone authorize "drive"` on your laptop where Firefox/Chrome can open
the login URL, paste the JSON token back into the VM prompt.

If the VM has a browser (we install Firefox/Chromium during setup if you
chose to): pick `Use auto config? = y` and let it open automatically.

Verify:
```bash
rclone lsd gdrive:
rclone mkdir gdrive:ZoomRecordings
echo smoke > ~/smoke.txt
rclone copy ~/smoke.txt gdrive:ZoomRecordings/
command rm ~/smoke.txt
```

### 3. Tell the recorder where to upload

The stop launcher inherits its environment from XFCE → systemd `--user`,
so set the var in the systemd user environment file (NOT `.bashrc`,
which the .desktop launcher never sources):

```bash
mkdir -p ~/.config/environment.d
echo 'ZOOM_REC_REMOTE=gdrive:ZoomRecordings' > ~/.config/environment.d/zoom-recorder.conf
# active on next session start; for the running session:
systemctl --user set-environment ZOOM_REC_REMOTE=gdrive:ZoomRecordings
DISPLAY=:1 dbus-update-activation-environment --systemd ZOOM_REC_REMOTE
```

After a VM reboot it just works without any of the manual `set-environment` /
`dbus-update-…` dance — those are only needed once to push the env into the
*currently running* XFCE without restarting it.

### 4. Test end-to-end

Click Start → wait a bit → click Stop. Expect three toasts:

```
Saved N part(s), <size> total — recording-…
Uploading N part(s) to gdrive:ZoomRecordings/…
Uploaded N part(s) to gdrive:ZoomRecordings/recording-…
```

Folder appears on drive.google.com under `ZoomRecordings/`. Unset
`ZOOM_REC_REMOTE` to disable uploads.

---

## Compression knobs

Inside `~/bin/zoom-record-start.sh`:

| Knob              | Current     | Effect                                      |
| ----------------- | ----------- | ------------------------------------------- |
| `-crf`            | 25          | 22 = larger/sharper, 28 = smaller           |
| `-r` (frame rate) | 15          | 10 cuts file ~30 %; 30 doubles it           |
| `-preset`         | slow        | `medium` if CPU-bound at 1080p; `veryslow` for max compression |
| `-tune`           | stillimage  | optimized for slides                        |
| audio `-b:a`      | 96 k        | 64 k for talk-only; 128 k for music         |
| `-video_size`     | auto-detect | `xdpyinfo` — matches Xvnc framebuffer       |
| `-segment_time`   | 900 (15 min) | Crash-safety chunk length. Override with `ZOOM_SEGMENT_SECONDS`. |

Approximate sizes at the defaults:

| Meeting length | 720p (older) | 1080p (current) |
| -------------- | ------------ | --------------- |
| 30 min         | 40–75 MB     | 80–150 MB       |
| 1 hour         | 80–150 MB    | 150–300 MB      |
| 2 hours        | 160–300 MB   | 300–600 MB      |

CPU at 1080p / `-preset slow` is ~65–75 % on t3.medium. For sustained
multi-hour recordings drop to `-preset medium` (~30 % less CPU, files ~10–15 %
larger).

---

## Troubleshooting

| Symptom                                | Likely cause / fix |
| -------------------------------------- | ------------------ |
| Silent recording                       | Zoom speaker is "Default" instead of **ZoomSink**. Open Zoom → Settings → Audio. |
| Black/empty recording                  | ffmpeg started before VNC. Make sure `vncserver :1` is running. |
| Auto-record didn't trigger             | Tail `~/recordings/.monitor.log`. Check `pgrep -af zoom-recorder-monitor.sh`. Check `wmctrl -l` shows a Zoom window. Toggle may be OFF (`~/recordings/.monitor.paused`). |
| Multiple `zoom_sink.N` after restart   | xstartup wasn't updated. Re-run `./setup-vm.sh`, or copy the latest xstartup. Unload extras: `for id in $(pactl list short modules \| grep null-sink \| awk '{print $1}' \| tail -n +2); do pactl unload-module $id; done` |
| Recording captures only top-left 720p area | Framebuffer ≠ ffmpeg capture size. Recording scripts auto-detect with `xdpyinfo`; if old hardcoded version is still installed, push the latest `vm-files/zoom-record-start.sh`. |
| `xtigervncviewer -via` "End of stream" | `-via` keeps SSH alive only ~20 s. Open `ssh <vm>` in a terminal first, then `xtigervncviewer localhost:5901`. |
| Desktop icons show as text             | XFCE 4.18 trust system: right-click → "Allow Launching", or rerun setup (it pre-trusts via `gio set`). |
| Zoom won't start                       | Missing `libxcb-cursor0`. `sudo apt install libxcb-cursor0`. |
| `dpkg interrupted` during apt          | `sudo dpkg --configure -a`, then re-run setup. |
| Public IP changed after EC2 stop/start | Update `HostName` in `~/.ssh/config`, or assign an Elastic IP. Tailscale IP stays the same. |
| VNC viewer "End of stream" after VM reboot | `vncserver@:1` should auto-start via systemd `--user` with linger. If it didn't: `ssh <vm> 'systemctl --user start vncserver@:1'` and inspect `systemctl --user status vncserver@:1 --no-pager`. Confirm linger: `loginctl show-user ubuntu \| grep Linger`. |
| Zoom keeps closing every ~90 seconds; multiple short recordings appear | `vncserver@:1` is in a restart loop. Check `journalctl --user -u vncserver@:1 -n 50`. The unit deliberately does **NOT** set `PIDFile=` because TigerVNC names its pidfile with `hostname` output (e.g. `<host>:1.pid`), which can change at runtime (Tailscale's MagicDNS rewrites the hostname). If you add `PIDFile=`, the pattern will eventually mismatch and systemd's start operation will time out → `Restart=on-failure` kicks → Xvnc + Zoom + ffmpeg get killed every ~90 s. Trade-off: `MainPID=0`, but the cgroup still tracks all children correctly. |
| "Upload to gdrive failed" + `~/recordings/.upload-*.log` is missing | You're on **snap** rclone. Its launcher fails when invoked from an xfce4-session-spawned process — journal shows `Activated service 'org.freedesktop.systemd1' failed: Process … exited with status 1`. Manual `rclone copy` from SSH still works, which is why this is easy to miss. Fix: install the .deb from rclone.org (see § auto-upload). |
| `empty token found - please run "rclone config reconnect gdrive:"` | OAuth token gone — most common after swapping snap rclone for the .deb. Snap stored the token under `~/snap/rclone/common/.config/rclone/`, which `snap remove rclone` deletes; the remote config in `~/.config/rclone/rclone.conf` survives but its token field is empty. Fix: `rclone config reconnect gdrive:`. |

---

## Cost summary

- **t3.medium on-demand**: ~$0.042/hr → 1-hour meeting ≈ $0.04
- **EBS gp3 30 GB**: ~$2.40/mo standing (paid whether running or stopped)
- **Outbound transfer**: ~$0.09/GB beyond free tier
- Spot pricing drops compute another ~70 %

Stop between meetings:

```bash
aws ec2 stop-instances --instance-ids <i-...>
```

---

## Sources

- [Zoom Meeting SDK headless Linux sample](https://github.com/zoom/meetingsdk-headless-linux-sample)
- [zoomrec — Xvfb/PulseAudio/ffmpeg bot](https://github.com/kastldratza/zoomrec)
- [Compressing lectures with CRF + ffmpeg](https://lou-kratz.medium.com/compressing-recorded-lectures-with-crf-and-ffmpeg-891a320a44bd)
- [rclone documentation](https://rclone.org/docs/)
- [Tailscale install](https://tailscale.com/download/linux)
