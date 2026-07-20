#!/usr/bin/env python3

"""
Deduplicate ~/.ssh/known_hosts, keeping the latest (last-in-file) entry for
each host key and dropping earlier duplicates.

ssh appends new host key entries to the end of known_hosts, so for any given
host the last matching entry is the most recently added one.

With HashKnownHosts enabled (the default on most distros), hostnames are
salted and hashed per-line, so two entries can't be compared by hostname.
Instead entries are grouped by (marker, keytype, key) - e.g. two lines with
the same ssh-rsa/ecdsa/ed25519 key are almost certainly the same host recorded
under different aliases (hostname vs IP vs FQDN) or re-added over time, not a
coincidental key collision between unrelated hosts.

Usage:
    ./ssh_known_hosts_dedupe.py [known_hosts_path] [--dry-run]

A timestamped backup is written next to the file before it is overwritten.
"""

import argparse
import os
import shutil
from datetime import datetime

DEFAULT_KNOWN_HOSTS = '~/.ssh/known_hosts'


def parse_key_group(line):
    """Return the grouping tuple for a known_hosts entry line, or None if the
    line is blank, a comment, or unparseable.

    Hashed hostnames (the default with HashKnownHosts) are salted per-line, so
    identical hosts get different literal text; those are grouped by
    (marker, keytype, key) alone. Plaintext hostnames are included in the
    group key so two distinct hosts that happen to share a key (e.g. cloned
    VM/container images that never regenerated their host key) are never
    merged into one."""
    stripped = line.strip()
    if not stripped or stripped.startswith('#'):
        return None

    tokens = stripped.split()

    if tokens[0].startswith('@'):
        if len(tokens) < 4:
            return None
        marker, hosts, keytype, key = tokens[0], tokens[1], tokens[2], tokens[3]
    else:
        if len(tokens) < 3:
            return None
        marker, hosts, keytype, key = '', tokens[0], tokens[1], tokens[2]

    if hosts.startswith('|1|'):
        return marker, keytype, key
    return marker, hosts, keytype, key


def dedupe_lines(lines):
    """Return (kept_lines, removed_count), keeping the last occurrence of
    each (marker, keytype, key) group and all non-key lines untouched."""
    groups = [parse_key_group(line) for line in lines]

    last_index_by_group = {}
    for i, group in enumerate(groups):
        if group is not None:
            last_index_by_group[group] = i

    kept = []
    removed = 0
    for i, (line, group) in enumerate(zip(lines, groups)):
        if group is None or last_index_by_group[group] == i:
            kept.append(line)
        else:
            removed += 1

    return kept, removed


def dedupe_known_hosts(path, dry_run):
    with open(path, 'rt') as f:
        lines = f.readlines()

    kept, removed = dedupe_lines(lines)

    print('%s: %d lines, %d duplicate entries, %d remaining' % (path, len(lines), removed, len(kept)))

    if removed == 0:
        print('Nothing to do')
        return

    if dry_run:
        print('Dry run, no changes written')
        return

    backup_path = '%s.bak.%s' % (path, datetime.now().strftime('%Y%m%d-%H%M%S'))
    shutil.copy2(path, backup_path)
    print('Backup saved to %s' % backup_path)

    with open(path, 'wt') as f:
        f.writelines(kept)

    print('Wrote %d lines to %s' % (len(kept), path))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('path', nargs='?', default=DEFAULT_KNOWN_HOSTS,
                         help='path to known_hosts file (default: %s)' % DEFAULT_KNOWN_HOSTS)
    parser.add_argument('--dry-run', action='store_true',
                         help='show what would change without modifying the file')
    args = parser.parse_args()

    path = os.path.expanduser(args.path)
    if not os.path.isfile(path):
        parser.error('file not found: %s' % path)

    dedupe_known_hosts(path, args.dry_run)


if __name__ == '__main__':
    main()
