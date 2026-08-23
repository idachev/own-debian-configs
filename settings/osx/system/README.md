# macOS system settings

Tree under `etc/` mirrors `/etc`, same idea as `settings/linux/system/etc`.

These are copies, not live links. Restore with `sudo cp` (do not symlink into `/etc`).

## sshd LAN-only

`etc/ssh/sshd_config.d/200-lan-only.conf` → `/etc/ssh/sshd_config.d/200-lan-only.conf`

Rejects SSH auth from outside `192.168.77.0/24` (this Mac's Wi-Fi) and localhost.
`100-macos.conf` is Apple's stock drop-in — not kept here.

### Restore

Remote Login must already be on (`System Settings → General → Sharing → Remote Login`,
or `sudo launchctl enable system/com.openssh.sshd`).

```
sudo cp etc/ssh/sshd_config.d/200-lan-only.conf /etc/ssh/sshd_config.d/200-lan-only.conf
sudo sshd -t
```

sshd is socket-activated: each new connection reads this file. No daemon restart.
Existing sessions keep the old rules until they disconnect.

If the LAN subnet changes, edit the `Match Address` line and copy again.
