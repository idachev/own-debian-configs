# Hermes VM — User Setup (deploy + hermes)

Secure user setup for a brand-new VM where you start with only `root`.

**Goal:** two accounts, least privilege.

- **`deploy`** — human admin account. SSH key login only, `sudo` for management.
- **`hermes`** — dedicated service account that runs the Hermes AI agent. **No sudo, no password, no SSH login.** Minimizes blast radius if the agent (or a prompt-injection / RCE) goes rogue.

> Firewall is handled **outside** the VM via the **Hetzner Cloud Firewall** — no UFW/iptables steps here. Just ensure SSH (22) and any agent port are allowed in the Hetzner Firewall.

Examples assume Ubuntu/Debian. On RHEL/Alma/Rocky use group `wheel` instead of `sudo`, and service `sshd` instead of `ssh`.

---

## 1. Create the admin user (`deploy`)

```bash
# as root
adduser deploy                 # set a strong password (used only for sudo prompts, optional — see step 6)
usermod -aG sudo deploy        # RHEL: usermod -aG wheel deploy
```

## 2. Install your SSH public key for `deploy`

On your **laptop**, generate a modern key if you don't have one:

```bash
ssh-keygen -t ed25519 -C "you@laptop"   # ed25519 = current recommended algorithm; use a passphrase
```

Copy it up (easiest while root login still works):

```bash
ssh-copy-id deploy@VM_IP
```

Or manually on the VM:

```bash
mkdir -p /home/deploy/.ssh
nano /home/deploy/.ssh/authorized_keys     # paste the PUBLIC key (id_ed25519.pub)
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys
```

Permissions matter — SSH refuses keys if the dir/file are too open.

**Verify in a second terminal that `ssh deploy@VM_IP` works BEFORE locking anything down.**

## 3. Create the agent service account (`hermes`)

```bash
# as root — no password, no sudo, no SSH login
adduser --disabled-password --gecos "" hermes
```

- Not in `sudo`/`wheel` → cannot escalate.
- No `authorized_keys` for it. Reach it via `sudo -u hermes -i` from `deploy`, or run it as a systemd service with `User=hermes`.
- **Never** give `hermes` sudo. That defeats the purpose of the account.

### Prefer a hardened systemd unit for the agent

Run the agent as a service with `User=hermes` plus sandboxing directives:

```ini
# /etc/systemd/system/hermes.service  (example skeleton)
[Service]
User=hermes
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/home/hermes/data      # only its own data dir
# ExecStart=...
```

## 4. Harden SSH (only after step 2 is verified)

Edit `/etc/ssh/sshd_config` (or a drop-in in `/etc/ssh/sshd_config.d/`):

```
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
```

Then:

```bash
sshd -t                  # validate config syntax FIRST
systemctl restart ssh    # RHEL: systemctl restart sshd
```

This eliminates SSH password brute-force and direct root login.

## 5. fail2ban — auto-ban brute-forcers

```bash
apt install fail2ban
# enable the sshd jail; defaults ban an IP after 5 failed attempts in 10 min
```

## 6. (Optional) Passwordless admin: lock password + NOPASSWD sudo

Convenient for a key-only admin account, but a tradeoff: security then collapses to
**a single factor — possession of the SSH private key.** Anyone/anything with a shell
as `deploy` gets instant silent root. Only do this if your key is passphrase-protected
and SSH is behind a VPN/Tailscale or the Hetzner Firewall restricts SSH to your IP.

```bash
# as root — use a drop-in, never edit /etc/sudoers directly
echo 'deploy ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/deploy
chmod 440 /etc/sudoers.d/deploy
visudo -c                 # validate syntax — do NOT skip (a bad sudoers can lock out escalation)
passwd -l deploy          # lock the login password (SSH is key-only anyway)
```

Test `sudo whoami` as `deploy` (should print `root` with no prompt) **before** closing your root session.

**Middle ground (keep 2 factors):** keep a password set on `deploy`, skip NOPASSWD —
you still type a password only at `sudo` prompts, so shell-access ≠ root.

## 7. Keep it patched

```bash
apt update && apt upgrade -y
apt install unattended-upgrades   # automatic security updates
```

---

## Password management cheatsheet (from root)

```bash
passwd deploy             # set/change deploy's password
passwd -l hermes          # lock a password (disable password login)
passwd -u hermes          # unlock
passwd -S deploy          # show password status
passwd -e deploy          # expire → force change at next login
```

---

## Summary

| Concern | Practice |
|---|---|
| Don't run as root | `deploy` sudo admin account |
| AI agent blast radius | `hermes` — non-sudo, no password, hardened systemd unit |
| Auth | SSH ed25519 keys only; `PasswordAuthentication no` |
| Root over SSH | `PermitRootLogin no` |
| Brute force | fail2ban (+ Hetzner Firewall outside the VM) |
| Agent egress | restrict outbound; write access only to its own data dir |
| Patching | `unattended-upgrades` |

**Golden rule:** NOPASSWD sudo (step 6) is for the human admin account only — never for `hermes`.
