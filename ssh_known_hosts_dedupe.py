#!/usr/bin/env python3

"""
Deduplicate ~/.ssh/known_hosts, keeping the latest (last-in-file) entry for
each PROVABLE duplicate and dropping earlier ones.

Two known_hosts lines are only ever merged when they are provably the same
hostname:

  - Plaintext hostnames are compared literally (they're visible in the file).
  - Hashed hostnames (the default with HashKnownHosts) are salted per-line,
    so they can't be compared directly. They are only merged when a supplied
    candidate hostname (from ~/.ssh/config `Host` entries and/or
    --hosts-file) verifies against the line's HMAC-SHA1(salt, hostname),
    exactly like `ssh-keygen -F` does.

Two hashed lines sharing the same key are NOT assumed to be the same host and
are NEVER merged on that basis alone: the same key is often shared across
several real aliases for one host (short name, FQDN, IP), and each alias is
an independent lookup key for ssh's verification - merging them would drop
the entry needed to verify whichever alias didn't survive, silently breaking
that connection (this previously broke `git push` to github.com when this
script grouped hashed entries by key alone).

Without any candidate hostnames, only byte-identical duplicate lines are
removed - always safe, but limited for a fully-hashed file. Pass
--ssh-config/--hosts-file to also verify and collapse duplicates for hosts
you actually use.

Usage:
    ./ssh_known_hosts_dedupe.py [known_hosts_path] [--dry-run]
                                 [--ssh-config PATH] [--no-ssh-config]
                                 [--hosts-file PATH]

A timestamped backup is written next to the file before it is overwritten.
"""

import argparse
import base64
import hashlib
import hmac
import os
import shutil
from datetime import datetime

DEFAULT_KNOWN_HOSTS = '~/.ssh/known_hosts'
DEFAULT_SSH_CONFIG = '~/.ssh/config'


def parse_entry(line):
    """Return (marker, hosts, keytype, key) for a known_hosts entry line, or
    None if the line is blank, a comment, or unparseable."""
    stripped = line.strip()
    if not stripped or stripped.startswith('#'):
        return None

    tokens = stripped.split()

    if tokens[0].startswith('@'):
        if len(tokens) < 4:
            return None
        return tokens[0], tokens[1], tokens[2], tokens[3]

    if len(tokens) < 3:
        return None

    return '', tokens[0], tokens[1], tokens[2]


def hashed_host_matches(hosts_field, hostname):
    """Return True if hosts_field (a `|1|salt|hash` known_hosts entry)
    verifies for the given literal hostname - the same check
    `ssh`/`ssh-keygen -F` perform."""
    if not hosts_field.startswith('|1|'):
        return False

    parts = hosts_field.split('|')
    if len(parts) != 4:
        return False

    try:
        salt = base64.b64decode(parts[2])
        expected = base64.b64decode(parts[3])
    except (ValueError, TypeError):
        return False

    computed = hmac.new(salt, hostname.encode(), hashlib.sha1).digest()
    return hmac.compare_digest(computed, expected)


def load_ssh_config_hosts(path):
    """Return literal (non-wildcard) hostnames from `Host` lines in an ssh
    client config file."""
    hosts = []
    if not os.path.isfile(path):
        return hosts

    with open(path, 'rt') as f:
        for line in f:
            stripped = line.strip()
            if not stripped or stripped.startswith('#'):
                continue

            parts = stripped.split(None, 1)
            if len(parts) != 2 or parts[0].lower() != 'host':
                continue

            for token in parts[1].split():
                if '*' not in token and '?' not in token:
                    hosts.append(token)

    return hosts


def load_hosts_file(path):
    """Return one candidate hostname per non-comment, non-blank line."""
    hosts = []
    with open(path, 'rt') as f:
        for line in f:
            stripped = line.strip()
            if stripped and not stripped.startswith('#'):
                hosts.append(stripped)
    return hosts


def group_key(entry, candidate_hostnames):
    """Return the grouping key used to decide duplicates for one entry.

    Defaults to the raw hosts field (byte-identical lines only). If the
    hosts field is hashed and verifies against exactly one candidate
    hostname, group by that verified hostname instead, so lines added at
    different times (different salts) for the SAME real hostname still
    collapse safely. A hashed line matching zero or more than one candidate
    is left ungrouped (conservative - never guess)."""
    marker, hosts_field, keytype, key = entry

    if hosts_field.startswith('|1|'):
        matches = [h for h in candidate_hostnames if hashed_host_matches(hosts_field, h)]
        if len(matches) == 1:
            return marker, 'verified:' + matches[0], keytype, key

    return marker, hosts_field, keytype, key


def dedupe_lines(lines, candidate_hostnames):
    """Return (kept_lines, removed_count, verified_removed_count)."""
    entries = [parse_entry(line) for line in lines]
    groups = [None if e is None else group_key(e, candidate_hostnames) for e in entries]

    last_index_by_group = {}
    for i, group in enumerate(groups):
        if group is not None:
            last_index_by_group[group] = i

    kept = []
    removed = 0
    verified_removed = 0
    for i, (line, group) in enumerate(zip(lines, groups)):
        if group is None or last_index_by_group[group] == i:
            kept.append(line)
        else:
            removed += 1
            if group[1].startswith('verified:'):
                verified_removed += 1

    return kept, removed, verified_removed


def dedupe_known_hosts(path, dry_run, candidate_hostnames):
    with open(path, 'rt') as f:
        lines = f.readlines()

    kept, removed, verified_removed = dedupe_lines(lines, candidate_hostnames)

    print('%s: %d lines, %d candidate hostnames to verify against' % (path, len(lines), len(candidate_hostnames)))
    print('%d duplicate entries removed (%d via verified hostname match), %d remaining' %
          (removed, verified_removed, len(kept)))

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
    parser.add_argument('--ssh-config', default=DEFAULT_SSH_CONFIG,
                         help='ssh client config to read literal Host entries from (default: %s)' % DEFAULT_SSH_CONFIG)
    parser.add_argument('--no-ssh-config', action='store_true',
                         help='do not read candidate hostnames from --ssh-config')
    parser.add_argument('--hosts-file',
                         help='extra file with one candidate hostname per line to verify hashed entries against')
    args = parser.parse_args()

    path = os.path.expanduser(args.path)
    if not os.path.isfile(path):
        parser.error('file not found: %s' % path)

    candidate_hostnames = []
    if not args.no_ssh_config:
        candidate_hostnames += load_ssh_config_hosts(os.path.expanduser(args.ssh_config))
    if args.hosts_file:
        candidate_hostnames += load_hosts_file(os.path.expanduser(args.hosts_file))
    candidate_hostnames = sorted(set(candidate_hostnames))

    dedupe_known_hosts(path, args.dry_run, candidate_hostnames)


if __name__ == '__main__':
    main()
