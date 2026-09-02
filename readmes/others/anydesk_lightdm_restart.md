# AnyDesk after a broken graphical session (idachev-p7560)

Linux Mint 21.3, LightDM + Cinnamon, AnyDesk `8.x`.

Remote `apt` upgrade can kill the X session. Cinnamon may keep running
on `:0` while logind has **no** graphical session on `seat0`. AnyDesk
then shows `display_server_not_supported` or `desk_rt_ipc_error`.

AnyDesk ID: `543619277`. SSH over ZeroTier still works.

## Fix that restored AnyDesk

From an SSH session:

```bash
sudo systemctl restart lightdm
sudo systemctl restart anydesk
```

Connect to `543619277` and log in at the LightDM greeter.

If the session drops after login (`desk_rt_ipc_error`):

```bash
sudo systemctl restart anydesk
```

Connect again to `543619277`.

## Why

AnyDesk attaches to the logind console session, not to a raw X process.
A missing console session is logged as `4294967295`. Restarting LightDM
creates a greeter session. Restarting AnyDesk binds to it.

A leftover `session-c2.scope` can block a new login:

```
pam_systemd: Failed to create session: Unit session-c2.scope already exists.
```

Stop that scope only if a new login still fails to register. Do **not**
stop `session-6.scope` — it holds `gocryptfs` for `storage_private_docs`.

## Checks

```bash
loginctl list-sessions
systemctl is-active anydesk lightdm
command grep -E 'UID:|console session|Client-ID' /var/log/anydesk.trace | command tail -n 20
```

Want a live greeter or Cinnamon session on `seat0`, and AnyDesk spawn
with `UID: 1000` (user) or `UID: 112` (greeter), not `UID: 0` / empty
`DPY`.
