# ssh_known_hosts_dedupe.py

Deduplicate `~/.ssh/known_hosts`, keeping the latest (last-in-file) entry for
each **provable** duplicate and dropping earlier ones.

Script lives at `~/bin/ssh_known_hosts_dedupe.py`.

## Usage

```bash
ssh_known_hosts_dedupe.py                              # dedupe ~/.ssh/known_hosts, using ~/.ssh/config Host entries
ssh_known_hosts_dedupe.py --dry-run                    # show what would change, no writes
ssh_known_hosts_dedupe.py --hosts-file extra_hosts.txt # also verify against these hostnames (one per line)
ssh_known_hosts_dedupe.py --no-ssh-config              # don't auto-load ~/.ssh/config Host entries
ssh_known_hosts_dedupe.py /path/to/known_hosts [--dry-run]
```

A timestamped `.bak.<date>-<time>` copy is written next to the file before it
is overwritten.

## Notes

- ssh appends new host key entries to the end of `known_hosts`, so for any
  given host the last matching entry is the most recently added one - that's
  what "latest" means here.
- Two lines are only ever merged when they're **provably** the same hostname:
  - Plaintext hostnames are compared literally.
  - Hashed hostnames (the default with `HashKnownHosts`) are salted per-line,
    so they can't be compared directly. They're only merged when a supplied
    candidate hostname (from `~/.ssh/config` `Host` entries and/or
    `--hosts-file`) verifies against the line's `HMAC-SHA1(salt, hostname)` -
    the same check `ssh-keygen -F` performs.
- **Two hashed lines sharing the same key are never merged on that basis
  alone.** The same key is often shared across several real aliases for one
  host (short name, FQDN, IP) - merging them would drop the entry needed to
  verify whichever alias didn't survive, silently breaking that connection.
  An earlier version of this script did merge same-key hashed lines and broke
  `git push` to github.com this way; that heuristic was removed.
- Without any candidate hostnames (`--no-ssh-config` and no `--hosts-file`),
  only byte-identical duplicate lines are removed - always safe, but limited
  for a fully-hashed file.
- `@cert-authority` / `@revoked` marker lines are grouped separately from
  plain entries with the same key.
- Comments, blank lines, and malformed/short lines are always preserved
  as-is.

## Requirements

None beyond Python 3's standard library.
