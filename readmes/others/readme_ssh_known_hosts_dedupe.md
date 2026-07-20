# ssh_known_hosts_dedupe.py

Deduplicate `~/.ssh/known_hosts`, keeping the latest (last-in-file) entry for
each host key and dropping earlier duplicates.

Script lives at `~/bin/ssh_known_hosts_dedupe.py`.

## Usage

```bash
ssh_known_hosts_dedupe.py                    # dedupe ~/.ssh/known_hosts in place
ssh_known_hosts_dedupe.py --dry-run          # show what would change, no writes
ssh_known_hosts_dedupe.py /path/to/known_hosts [--dry-run]
```

A timestamped `.bak.<date>-<time>` copy is written next to the file before it
is overwritten.

## Notes

- ssh appends new host key entries to the end of `known_hosts`, so for any
  given host the last matching entry is the most recently added one - that's
  what "latest" means here.
- With `HashKnownHosts` enabled (the default on most distros), hostnames are
  salted and hashed per-line, so entries can't be compared by hostname.
  Entries are instead grouped by `(marker, keytype, key)` - two hashed lines
  with the same key are almost certainly the same host recorded under
  different aliases (hostname vs IP vs FQDN) or re-added over time.
- Plaintext (non-hashed) hostnames are compared literally in addition to the
  key, so two genuinely different hosts that happen to share an identical key
  (e.g. cloned VM/container images that never regenerated their host key) are
  never merged.
- `@cert-authority` / `@revoked` marker lines are grouped separately from
  plain entries with the same key.
- Comments, blank lines, and malformed/short lines are always preserved
  as-is.

## Requirements

None beyond Python 3's standard library.
