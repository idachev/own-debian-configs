#!/usr/bin/env bash
# One-shot Zoom recorder VM setup. Run on a fresh Ubuntu 24.04/26.04 cloud VM
# as the default sudo-capable user (e.g. ubuntu). Idempotent — re-runs are safe.
#
# Usage:
#   ./setup-vm.sh
#
# Environment knobs:
#   VNC_PASSWORD          (default: random 16-char) — VNC password
#   VNC_GEOMETRY          (default: 1920x1080)      — framebuffer size, also recording size
#   BIND_LOCALHOST_ONLY   (default: no)             — yes: VNC only on lo. no: lo + Tailscale
#   ENABLE_TAILSCALE      (default: yes)            — install + auth Tailscale
#   ENABLE_ZOOM           (default: yes)            — install Zoom client
#   ENABLE_DESKTOP_ICONS  (default: yes)            — copy start/stop scripts + launchers
#
# Companion vm-files/ directory must be next to this script (or pointed at via
# VM_FILES_DIR env var).

set -euo pipefail

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
log()   { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn()  { printf '\n\033[1;33m!! %s\033[0m\n' "$*"; }
fatal() { printf '\n\033[1;31m## %s\033[0m\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] && fatal "Run as a normal user with sudo, not root."
sudo -v || fatal "sudo access required."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_FILES_DIR="${VM_FILES_DIR:-$SCRIPT_DIR/vm-files}"
[[ -d "$VM_FILES_DIR" ]] || fatal "vm-files dir not found at: $VM_FILES_DIR"

VNC_PASSWORD="${VNC_PASSWORD:-$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)}"
BIND_LOCALHOST_ONLY="${BIND_LOCALHOST_ONLY:-no}"
ENABLE_TAILSCALE="${ENABLE_TAILSCALE:-yes}"
ENABLE_ZOOM="${ENABLE_ZOOM:-yes}"
ENABLE_DESKTOP_ICONS="${ENABLE_DESKTOP_ICONS:-yes}"

# ----------------------------------------------------------------------------
# 1. Base packages
# ----------------------------------------------------------------------------
log "Updating apt and installing base packages"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update
sudo dpkg --configure -a            # repair any previous interrupted runs
sudo apt-get -y \
  -o Dpkg::Options::=--force-confdef \
  -o Dpkg::Options::=--force-confold \
  upgrade
sudo apt-get install -y \
  xfce4 xfce4-goodies dbus-x11 \
  tigervnc-standalone-server tigervnc-common \
  pulseaudio pulseaudio-utils pavucontrol \
  ffmpeg wget curl ca-certificates \
  libxcb-xtest0 libxcb-cursor0 \
  wmctrl xdotool x11-utils \
  openssl

# ----------------------------------------------------------------------------
# 2. TigerVNC: password, xstartup, config
# ----------------------------------------------------------------------------
log "Configuring TigerVNC"
mkdir -p "$HOME/.config/tigervnc"

echo "$VNC_PASSWORD" | vncpasswd -f > "$HOME/.config/tigervnc/passwd"
chmod 600 "$HOME/.config/tigervnc/passwd"

cat > "$HOME/.config/tigervnc/xstartup" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

# Audio: PulseAudio + null sink. Idempotent — pulseaudio is a user daemon
# that persists across Xvnc restarts, so only load the sink if missing.
pulseaudio --start 2>/dev/null || true
if ! pactl list short sinks 2>/dev/null | grep -qE '^[0-9]+[[:space:]]+zoom_sink[[:space:]]'; then
  pactl load-module module-null-sink \
    sink_name=zoom_sink \
    sink_properties=device.description=ZoomSink 2>/dev/null || true
fi
pactl set-default-sink zoom_sink 2>/dev/null || true

exec startxfce4
EOF
chmod +x "$HOME/.config/tigervnc/xstartup"

LOCALHOST_LINE="localhost=no"
[[ "$BIND_LOCALHOST_ONLY" == "yes" ]] && LOCALHOST_LINE="localhost=yes"
GEOMETRY="${VNC_GEOMETRY:-1920x1080}"
cat > "$HOME/.config/tigervnc/config" <<EOF
geometry=$GEOMETRY
depth=24
$LOCALHOST_LINE
# Reject viewer-initiated framebuffer resize so recording stays exactly $GEOMETRY
AcceptSetDesktopSize=0
EOF

log "Starting VNC server on :1"
vncserver -kill :1 2>/dev/null || true
sleep 1
vncserver :1

# ----------------------------------------------------------------------------
# 2b. Persist VNC across reboots via systemd --user
# ----------------------------------------------------------------------------
log "Registering vncserver@:1 as a systemd --user service"
mkdir -p "$HOME/.config/systemd/user"
install -m 644 "$VM_FILES_DIR/vncserver@.service" \
  "$HOME/.config/systemd/user/vncserver@.service"

systemctl --user daemon-reload
# Enable for boot — does NOT take over the already-running instance.
systemctl --user enable 'vncserver@:1.service' || true

# Linger so user manager starts at boot without a login, which is what runs
# systemd --user services like vncserver@:1.
sudo loginctl enable-linger "$USER"

# ----------------------------------------------------------------------------
# 3. Audio: PulseAudio + null sink for current session
# ----------------------------------------------------------------------------
log "Ensuring PulseAudio + null sink available now (non-VNC sessions)"
pulseaudio --start 2>/dev/null || true
pactl list short sinks 2>/dev/null | grep -q 'zoom_sink' || \
  pactl load-module module-null-sink \
    sink_name=zoom_sink \
    sink_properties=device.description=ZoomSink >/dev/null
pactl set-default-sink zoom_sink 2>/dev/null || true

# ----------------------------------------------------------------------------
# 4. Zoom client
# ----------------------------------------------------------------------------
if [[ "$ENABLE_ZOOM" == "yes" ]]; then
  log "Installing Zoom Linux client"
  if ! command -v zoom >/dev/null; then
    cd /tmp
    wget -q --show-progress https://zoom.us/client/latest/zoom_amd64.deb
    sudo apt-get install -y ./zoom_amd64.deb
    rm -f zoom_amd64.deb
    cd - >/dev/null
  else
    log "Zoom already installed ($(zoom --version 2>/dev/null | tail -1 || echo unknown))"
  fi
else
  warn "Skipping Zoom install (ENABLE_ZOOM=$ENABLE_ZOOM)"
fi

# ----------------------------------------------------------------------------
# 5. Tailscale (optional, interactive auth)
# ----------------------------------------------------------------------------
if [[ "$ENABLE_TAILSCALE" == "yes" ]]; then
  log "Installing Tailscale"
  if ! command -v tailscale >/dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sudo sh
  else
    log "Tailscale already installed: $(tailscale version | head -1)"
  fi
  if ! sudo tailscale status >/dev/null 2>&1; then
    log "Run the following AND open the printed URL to authenticate:"
    log "   sudo tailscale up --qr"
    warn "Skipping auto 'tailscale up' (interactive). Run it manually after setup completes."
  else
    log "Tailscale already authenticated. IP: $(sudo tailscale ip -4)"
  fi
else
  warn "Skipping Tailscale (ENABLE_TAILSCALE=$ENABLE_TAILSCALE)"
fi

# ----------------------------------------------------------------------------
# 6. Desktop icons + bin scripts
# ----------------------------------------------------------------------------
if [[ "$ENABLE_DESKTOP_ICONS" == "yes" ]]; then
  log "Installing recording scripts and desktop launchers"
  mkdir -p "$HOME/bin" "$HOME/Desktop" "$HOME/recordings" \
           "$HOME/.config/autostart"

  install -m 755 "$VM_FILES_DIR/zoom-record-start.sh"            "$HOME/bin/"
  install -m 755 "$VM_FILES_DIR/zoom-record-stop.sh"             "$HOME/bin/"
  install -m 755 "$VM_FILES_DIR/record-ad-hoc.sh"                "$HOME/bin/"
  install -m 755 "$VM_FILES_DIR/zoom-recorder-monitor.sh"        "$HOME/bin/"
  install -m 755 "$VM_FILES_DIR/zoom-recorder-monitor-toggle.sh" "$HOME/bin/"

  # Generate .desktop launchers with the real $HOME path baked into Exec=.
  # vm-files/*.desktop are templates that use /home/ubuntu/... — rewrite to $HOME.
  for stem in zoom-record-start zoom-record-stop zoom-recorder-monitor-toggle; do
    src="$VM_FILES_DIR/${stem}.desktop"
    dst="$HOME/Desktop/${stem}.desktop"
    sed "s|/home/ubuntu/bin/|$HOME/bin/|g" "$src" > "$dst"
    chmod 755 "$dst"
    gio set "$dst" 'metadata::xfce-exe-checksum' \
      "$(sha256sum "$dst" | cut -d' ' -f1)" 2>/dev/null || true
  done

  # XFCE autostart entry for the monitor (runs when VNC session starts).
  sed "s|/home/ubuntu/bin/|$HOME/bin/|g" \
    "$VM_FILES_DIR/zoom-recorder-monitor.autostart.desktop" \
    > "$HOME/.config/autostart/zoom-recorder-monitor.desktop"
  chmod 644 "$HOME/.config/autostart/zoom-recorder-monitor.desktop"
else
  warn "Skipping desktop icons (ENABLE_DESKTOP_ICONS=$ENABLE_DESKTOP_ICONS)"
fi

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
log "Setup complete."
cat <<EOF

  VNC display      :1
  VNC port         5901  (binding: $([[ "$BIND_LOCALHOST_ONLY" == yes ]] && echo "localhost only" || echo "all interfaces"))
  VNC password     $VNC_PASSWORD
  Recordings dir   $HOME/recordings/

  Desktop icons    $([[ "$ENABLE_DESKTOP_ICONS" == yes ]] && echo "$HOME/Desktop/zoom-record-{start,stop}.desktop" || echo "(skipped)")
  Tailscale        $([[ "$ENABLE_TAILSCALE" == yes ]] && (sudo tailscale ip -4 2>/dev/null || echo "installed, not yet authenticated — run: sudo tailscale up --qr") || echo "(skipped)")

  Next steps:
    1. From the VNC viewer, open Zoom → Settings → Audio → Speaker = ZoomSink.
    2. (Optional) Click "Start Recording" desktop icon to test.
    3. If Tailscale was not auto-authenticated, run:    sudo tailscale up --qr
EOF
