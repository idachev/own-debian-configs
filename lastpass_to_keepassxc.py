#!/usr/bin/env python3

"""
Convert a LastPass CSV export into a native KeePassXC (.kdbx) database.

LastPass export (Account -> Advanced -> Export) produces a CSV with headers:

    url,username,password,totp,extra,name,grouping,fav

Older exports omit the `totp` and `fav` columns; this script handles both since
it reads by header name, not position.

Features:
  * Master password is prompted interactively (never hardcoded). It can also be
    supplied via the KEEPASS_MASTER_PASSWORD environment variable for
    automation.
  * The LastPass folder hierarchy (the `grouping` column, '\\'-separated) is
    recreated as nested KeePassXC groups.
  * TOTP seeds (the `totp` column) are migrated as a KeePassXC-readable `otp`
    attribute so 2FA codes keep working.
  * Refuses to overwrite an existing database unless --force is given.

Usage:
    ./lastpass_to_keepassxc.py [-i lastpass_export.csv] [-o vault.kdbx] [--force]

Requires: pip install pykeepass
"""

import argparse
import csv
import os
import re
import sys
from getpass import getpass

try:
    from pykeepass import create_database
except ImportError:
    sys.exit("pykeepass is not installed. Run: pip install pykeepass")


# LastPass marks secure notes with this sentinel in the url column.
SECURE_NOTE_URL = "http://sn"
ENV_PASSWORD = "KEEPASS_MASTER_PASSWORD"


def parse_args():
    parser = argparse.ArgumentParser(
        description="Convert a LastPass CSV export to a KeePassXC database.")
    parser.add_argument(
        "-i", "--input", default="lastpass_export.csv",
        help="LastPass CSV export path (default: lastpass_export.csv)")
    parser.add_argument(
        "-o", "--output", default="my_perfect_vault.kdbx",
        help="Output .kdbx path (default: my_perfect_vault.kdbx)")
    parser.add_argument(
        "--force", action="store_true",
        help="Overwrite the output database if it already exists")
    return parser.parse_args()


def prompt_master_password():
    """Return the master password from the environment or an interactive prompt."""
    env_password = os.environ.get(ENV_PASSWORD)
    if env_password:
        print("NOTE: using master password from %s environment variable"
              % ENV_PASSWORD, file=sys.stderr)
        return env_password

    while True:
        password = getpass("Master password for the new vault: ")
        if not password:
            print("Password cannot be empty.", file=sys.stderr)
            continue
        confirm = getpass("Confirm master password: ")
        if password != confirm:
            print("Passwords do not match, try again.", file=sys.stderr)
            continue
        return password


def get_or_create_group(kp, parent, grouping):
    """Walk/create the nested group path described by a LastPass grouping string."""
    group = parent
    if not grouping:
        return group

    # LastPass nests folders with backslashes; tolerate forward slashes too.
    parts = [p for p in grouping.replace("/", "\\").split("\\") if p.strip()]
    for name in parts:
        child = next(
            (g for g in group.subgroups if g.name == name), None)
        if child is None:
            child = kp.add_group(group, name)
        group = child
    return group


# Characters the KDBX XML format cannot store: control chars except tab,
# newline and carriage return (XML 1.0 valid range).
XML_INVALID_RE = re.compile(
    "[^\x09\x0a\x0d\x20-\ud7ff\ue000-\ufffd"
    "\U00010000-\U0010ffff]")


def sanitize(value):
    """Strip XML-incompatible control characters that lxml/KDBX rejects."""
    if not value:
        return value
    return XML_INVALID_RE.sub("", value)


def dump_row(line_num, row, reason):
    """Print a CSV row verbatim (repr) so problem bytes are visible."""
    print("--- %s at CSV line %d ---" % (reason, line_num), file=sys.stderr)
    for key, value in row.items():
        print("    %s = %r" % (key, value), file=sys.stderr)


def build_otp_uri(totp_secret, title):
    """Turn a LastPass TOTP seed into a KeePassXC-readable otpauth URI, or None."""
    secret = (totp_secret or "").strip()
    if not secret:
        return None
    # If LastPass already exported a full otpauth URL, keep it; otherwise wrap
    # the raw base32 seed in the otpauth format KeePassXC expects.
    if secret.lower().startswith("otpauth://"):
        return secret
    label = title or "LastPass"
    return ("otpauth://totp/%s?secret=%s&period=30&digits=6&issuer=%s"
            % (label, secret, label))


def convert(args):
    if not os.path.isfile(args.input):
        sys.exit("Input CSV not found: %s" % args.input)

    if os.path.exists(args.output) and not args.force:
        sys.exit(
            "Output already exists: %s (use --force to overwrite)" % args.output)

    password = prompt_master_password()

    kp = create_database(args.output, password=password)
    root = kp.root_group
    lastpass_root = kp.add_group(root, "LastPass Migrated")

    count = 0
    skipped = 0
    sanitized_titles = []
    failed_rows = []
    with open(args.input, mode="r", encoding="utf-8", newline="") as f:
        # The csv module itself rejects NUL bytes, so drop them at the stream
        # level before parsing.
        reader = csv.DictReader(line.replace("\0", "") for line in f)
        for row in reader:
            # Skip blank trailing lines that LastPass sometimes emits.
            if not any((value or "").strip() for value in row.values()):
                skipped += 1
                continue

            title = (row.get("name") or "").strip() or "Untitled Entry"
            url = (row.get("url") or "").strip()
            username = row.get("username") or ""
            entry_password = row.get("password") or ""
            notes = row.get("extra") or ""
            grouping = (row.get("grouping") or "").strip()
            totp = row.get("totp") or ""

            # Real exports may contain control characters (e.g. NULL bytes in
            # notes) that the KDBX XML format cannot store; strip them.
            fields = [title, url, username, entry_password, notes, grouping]
            cleaned = [sanitize(value) for value in fields]
            if cleaned != fields:
                sanitized_titles.append(title)
                dump_row(reader.line_num, row, "Sanitized row")
                title, url, username, entry_password, notes, grouping = cleaned

            # Secure notes carry no real URL; drop the sentinel.
            if url == SECURE_NOTE_URL:
                url = ""

            try:
                group = get_or_create_group(kp, lastpass_root, grouping)
                kp.add_entry(
                    destination_group=group,
                    title=title,
                    username=username,
                    password=entry_password,
                    url=url,
                    notes=notes,
                    otp=build_otp_uri(totp, title),
                    # Real LastPass exports often repeat titles in a folder.
                    force_creation=True)
                count += 1
            except Exception as exc:
                failed_rows.append((reader.line_num, title))
                print("ERROR: %s" % exc, file=sys.stderr)
                dump_row(reader.line_num, row, "Failed row")

    kp.save()

    # Self-check: reopen the saved vault with the same password so a silent
    # mismatch is caught here instead of at first unlock in KeePassXC.
    from pykeepass import PyKeePass
    PyKeePass(args.output, password=password)
    print("Verified: vault reopens with the provided master password")

    print("Imported %d entries into %s" % (count, args.output))
    if skipped:
        print("Skipped %d blank rows" % skipped)
    if sanitized_titles:
        print("Stripped XML-invalid control characters from %d entries:"
              % len(sanitized_titles))
        for entry_title in sanitized_titles:
            print("  - %s" % entry_title)
        print("Review these entries in KeePassXC; the removed bytes were not"
              " storable in the KDBX format.")
    if failed_rows:
        print("FAILED to import %d rows (see dumps above):" % len(failed_rows),
              file=sys.stderr)
        for line_num, entry_title in failed_rows:
            print("  - CSV line %d: %s" % (line_num, entry_title),
                  file=sys.stderr)
        sys.exit(1)


def main():
    convert(parse_args())


if __name__ == "__main__":
    main()
