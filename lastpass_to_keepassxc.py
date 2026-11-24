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
  * Delta mode compares two LastPass exports and prepares a separate database
    for KeePassXC's Database > Merge From Database command.

Usage:
    ./lastpass_to_keepassxc.py [-i lastpass_export.csv] [-o vault.kdbx] [--force]
    ./lastpass_to_keepassxc.py --previous old.csv -i new.csv --base vault.kdbx -o changes.kdbx

Requires: pip install pykeepass
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import sys
from collections import Counter, defaultdict
from copy import deepcopy
from dataclasses import dataclass
from datetime import timedelta
from getpass import getpass
from pathlib import Path
from tempfile import TemporaryDirectory

try:
    from pykeepass import PyKeePass, create_database
    from pykeepass.entry import Entry
except ImportError:
    sys.exit("pykeepass is not installed. Run: pip install pykeepass")


# LastPass marks secure notes with this sentinel in the url column.
SECURE_NOTE_URL = "http://sn"
ENV_PASSWORD = "KEEPASS_MASTER_PASSWORD"
BASE_PASSWORD = "KEEPASS_BASE_PASSWORD"
MIGRATION_GROUP = "LastPass Migrated"
LEGACY_OTP_KEYS = {"TOTP Seed", "TOTP Settings", "TimeOtp-Secret-Base32"}


def parse_args():
    parser = argparse.ArgumentParser(
        description="Convert a LastPass CSV export to a KeePassXC database.")
    parser.add_argument("-i", "--input",
                        help="LastPass CSV export path (default: lastpass_export.csv)")
    parser.add_argument("-o", "--output",
                        help="Output database path (default: my_perfect_vault.kdbx)")
    parser.add_argument(
        "--force", action="store_true",
        help="Overwrite the output database if it already exists")
    parser.add_argument("--previous", help="Previous LastPass CSV export for delta mode")
    parser.add_argument("--base", help="Current KeePassXC database for delta mode")
    parser.add_argument("--base-keyfile", help="Key file for the current database")
    parser.add_argument("--dry-run", action="store_true",
                        help="Compare the snapshots and base without writing a delta")
    args = parser.parse_args()
    if args.previous or args.base or args.base_keyfile or args.dry_run:
        if not all((args.previous, args.base, args.input)):
            parser.error("delta mode requires --previous, --base and --input")
        if not args.output and not args.dry_run:
            parser.error("delta mode requires --output unless --dry-run is set")
    else:
        args.input = args.input or "lastpass_export.csv"
        args.output = args.output or "my_perfect_vault.kdbx"
    return args


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


def group_parts(grouping):
    """Parse the folder separators accepted by the original converter."""
    return tuple(part for part in grouping.replace("/", "\\").split("\\") if part.strip())


def get_or_create_group(kp, parent, grouping):
    """Walk/create the nested group path described by a LastPass grouping string."""
    group = parent
    for name in group_parts(grouping):
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
    lastpass_root = kp.add_group(root, MIGRATION_GROUP)

    count = 0
    skipped = 0
    sanitized_rows = []
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
                sanitized_rows.append(reader.line_num)
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
            except Exception:
                failed_rows.append(reader.line_num)

    kp.save()

    # Self-check: reopen the saved vault with the same password so a silent
    # mismatch is caught here instead of at first unlock in KeePassXC.
    PyKeePass(args.output, password=password)
    print("Verified: vault reopens with the provided master password")

    print("Imported %d entries into %s" % (count, args.output))
    if skipped:
        print("Skipped %d blank rows" % skipped)
    if sanitized_rows:
        print("Stripped XML-invalid control characters from %d entries:"
              % len(sanitized_rows))
        for line_num in sanitized_rows:
            print("  - CSV line %d" % line_num)
        print("Review these entries in KeePassXC; the removed bytes were not"
              " storable in the KDBX format.")
    if failed_rows:
        print("FAILED to import %d rows:" % len(failed_rows),
              file=sys.stderr)
        for line_num in failed_rows:
            print("  - CSV line %d" % line_num, file=sys.stderr)
        sys.exit(1)


class DeltaError(Exception):
    """An error whose message can be shown without exposing vault contents."""


@dataclass(frozen=True, repr=False)
class LastPassRow:
    line: int
    path: tuple
    title: str
    url: str
    username: str
    password: str
    notes: str
    otp: str | None

    @property
    def identity(self):
        return self.path, self.title, self.url, self.username

    def values(self, compare_otp):
        return self.password, self.notes, (self.otp or "") if compare_otp else ""


@dataclass(frozen=True)
class Review:
    reason: str
    old_rows: tuple
    new_rows: tuple

    def report(self):
        locations = []
        for label, rows in (("old CSV", self.old_rows), ("new CSV", self.new_rows)):
            if rows:
                lines = ", ".join(str(row.line) for row in rows)
                locations.append(f"{label} line(s) {lines}")
        print(f"Review {', '.join(locations)} ({self.reason})", file=sys.stderr)


@dataclass(frozen=True, repr=False)
class DeltaEntry:
    row: LastPassRow
    groups: tuple
    current: Entry | None
    changes: dict


def read_snapshot(filename, label):
    required = {"url", "username", "password", "extra", "name", "grouping"}
    used_columns = required | {"totp"}
    rows = defaultdict(list)
    line = 1
    try:
        with open(filename, encoding="utf-8-sig", newline="") as source:
            reader = csv.reader(source, strict=True)
            header = next(reader, [])
            if not required.issubset(header) or len(header) != len(set(header)):
                raise DeltaError(f"{label} has missing or duplicate CSV headers")
            has_otp = "totp" in header
            while True:
                line = reader.line_num + 1
                fields = next(reader, None)
                if fields is None:
                    break
                if not fields or (len(fields) == len(header) and not any(
                        value.strip() for value in fields)):
                    continue
                if len(fields) != len(header):
                    raise DeltaError(f"{label} line {line} has the wrong number of columns")
                values = dict(zip(header, fields))
                if any(XML_INVALID_RE.search(values.get(key, "")) for key in used_columns):
                    raise DeltaError(f"{label} line {line} has characters KDBX cannot store")
                title = values["name"].strip() or "Untitled Entry"
                url = values["url"].strip()
                row = LastPassRow(
                    line, (MIGRATION_GROUP, *group_parts(values["grouping"].strip())), title,
                    "" if url == SECURE_NOTE_URL else url, values["username"],
                    values["password"], values["extra"],
                    (build_otp_uri(values["totp"], title) or "") if has_otp else None,
                )
                rows[row.identity].append(row)
    except (OSError, UnicodeError, csv.Error):
        raise DeltaError(f"Could not read {label} near line {line}") from None
    return rows, has_otp


def unmatched_rows(rows, other, compare_otp):
    remaining = Counter(row.values(compare_otp) for row in other)
    unmatched = []
    for row in rows:
        values = row.values(compare_otp)
        if remaining[values]:
            remaining[values] -= 1
        else:
            unmatched.append(row)
    return tuple(unmatched)


def compare_snapshots(previous, incoming, compare_otp):
    candidates = []
    reviews = []
    unmatched_old = False
    for identity, old_rows in previous.items():
        new_rows = incoming.get(identity, ())
        old_remaining = unmatched_rows(old_rows, new_rows, compare_otp)
        new_remaining = unmatched_rows(new_rows, old_rows, compare_otp)
        if not old_remaining and not new_remaining:
            continue
        if len(old_rows) == len(new_rows) == 1:
            candidates.append((old_rows[0], new_rows[0]))
            continue
        unmatched_old |= bool(old_remaining)
        reason = "ambiguous CSV identity" if new_rows else "missing from new CSV"
        reviews.append(Review(reason, old_remaining, new_remaining))
    for identity, new_rows in incoming.items():
        if identity in previous:
            continue
        if len(new_rows) > 1 or unmatched_old:
            reason = "ambiguous CSV identity" if len(new_rows) > 1 else "possible rename or move"
            reviews.append(Review(reason, (), new_rows))
        else:
            candidates.append((None, new_rows[0]))
    return candidates, reviews


def base_groups(root, path):
    groups = []
    parent = root
    for name in path:
        matches = [group for group in parent.subgroups if group.name == name] if parent else []
        if len(matches) > 1:
            raise DeltaError("ambiguous group path in KeePassXC")
        parent = matches[0] if matches else None
        groups.append(parent)
    if groups[0] is None:
        raise DeltaError("LastPass Migrated group is missing from KeePassXC")
    return tuple(groups)


def reconcile_entry(old, row, current):
    """Return the subset of incoming fields that can replace their old values."""
    changes = {}
    for field in ("password", "notes", "otp"):
        incoming = getattr(row, field)
        if incoming is None:
            continue
        before = getattr(old, field)
        if incoming == before or (before is None and not incoming):
            continue
        if field == "otp" and LEGACY_OTP_KEYS.intersection(current._element.xpath("String/Key/text()")):
            raise DeltaError("conflicting legacy otp in KeePassXC")
        existing = getattr(current, field) or ""
        if existing == incoming:
            continue
        if before is None or existing != before:
            raise DeltaError(f"conflicting {field} in KeePassXC")
        changes[field] = incoming
    return changes


def plan_delta(base, candidates, reviews):
    entries_by_identity = defaultdict(list)
    if candidates:
        for entry in base.entries:
            signature = entry.title or "", entry.url or "", entry.username or ""
            entries_by_identity[signature].append(entry)

    updates = []
    already_applied = 0
    for old, row in candidates:
        try:
            groups = base_groups(base.root_group, row.path)
            destination = groups[-1]
            related = entries_by_identity[row.identity[1:]]
            matches = [entry for entry in related
                       if destination is not None and entry.group == destination]
            if len(matches) > 1:
                raise DeltaError("ambiguous entry identity in KeePassXC")
            current = matches[0] if matches else None
            if old is None and current is None:
                if related:
                    raise DeltaError("matching identity in another KeePassXC group")
                updates.append(DeltaEntry(row, groups, None, {}))
                continue
            if current is None:
                raise DeltaError("original entry is missing from KeePassXC")
            if old is None:
                if row.otp is not None and LEGACY_OTP_KEYS.intersection(
                        current._element.xpath("String/Key/text()")):
                    raise DeltaError("conflicting legacy otp in KeePassXC")
                if any(getattr(row, field) is not None
                       and getattr(row, field) != (getattr(current, field) or "")
                       for field in ("password", "notes", "otp")):
                    raise DeltaError("new CSV entry collides with a different KeePassXC entry")
                already_applied += 1
                continue
            changes = reconcile_entry(old, row, current)
            if changes:
                updates.append(DeltaEntry(row, groups, current, changes))
            else:
                already_applied += 1
        except DeltaError as error:
            reviews.append(Review(str(error), (old,) if old else (), (row,)))
    return updates, already_applied


def validate_output(args):
    output = Path(args.output)
    for source in (args.input, args.previous, args.base, args.base_keyfile):
        if not source:
            continue
        if (output.resolve() == Path(source).resolve()
                or (output.exists() and output.samefile(source))):
            raise DeltaError("Output refers to an input file")
    if os.path.lexists(output) and not args.force:
        raise DeltaError("Output already exists (use --force to replace it)")
    return output


def copy_xml_for_delta(element, base, delta):
    """Copy a node, translating timestamps when the source is KDBX 3."""
    result = deepcopy(element)
    if base.version[0] != delta.version[0]:
        stamps = result.xpath(
            ".//Times/*[not(self::Expires or self::UsageCount)]"
            " | .//CustomData/Item/LastModificationTime"
            " | self::Times/*[not(self::Expires or self::UsageCount)]"
            " | self::Icon/LastModificationTime"
        )
        for stamp in stamps:
            if stamp.text:
                stamp.text = delta._encode_time(base._decode_time(stamp.text))
    return result


def delta_group(delta, base, path, source_groups, groups):
    parent = delta.root_group
    for depth, (name, source) in enumerate(zip(path, source_groups), 1):
        key = path[:depth]
        if key not in groups:
            group = delta.add_group(parent, name)
            if source is not None:
                group.uuid = source.uuid
                group._element.replace(group._element.find("Times"),
                                       copy_xml_for_delta(source._element.find("Times"), base, delta))
                icon = source._element.find("CustomIconUUID")
                if icon is not None:
                    group._element.append(deepcopy(icon))
            groups[key] = group
        parent = groups[key]
    return parent


def populate_delta(delta, base, updates):
    groups = {}
    binary_ids = {}
    binaries = base.binaries
    for update in updates:
        row = update.row
        group = delta_group(delta, base, row.path, update.groups, groups)
        if update.current is None:
            delta.add_entry(group, row.title, row.username, row.password, url=row.url,
                            notes=row.notes, otp=row.otp or None, force_creation=True)
            continue

        element = copy_xml_for_delta(update.current._element, base, delta)
        # Current and historical attachments may share a binary, or refer to different ones.
        for value in element.xpath(".//Binary/Value[@Ref]"):
            old_id = int(value.get("Ref"))
            if old_id not in binary_ids:
                binary_ids[old_id] = delta.add_binary(binaries[old_id])
            value.set("Ref", str(binary_ids[old_id]))
        entry = Entry(element=element, kp=delta)
        group.append(entry)
        for field, value in update.changes.items():
            if field == "otp" and not value:
                element.remove(element.xpath("String[Key='otp']")[0])
            else:
                setattr(entry, field, value)
        entry.mtime = update.current.mtime.replace(microsecond=0) + timedelta(seconds=1)

    referenced_icons = set(delta.tree.xpath("/KeePassFile/Root//CustomIconUUID/text()"))
    for icon in base.tree.xpath("/KeePassFile/Meta/CustomIcons/Icon"):
        if icon.findtext("UUID") in referenced_icons:
            container = delta.tree.find("Meta/CustomIcons")
            if container is None:
                meta = delta.tree.find("Meta")
                container = meta.makeelement("CustomIcons")
                meta.append(container)
            container.append(copy_xml_for_delta(icon, base, delta))


def write_delta(args, base, updates):
    password = prompt_master_password()
    output = validate_output(args)
    with TemporaryDirectory(prefix=".lastpass-delta-", dir=output.parent) as folder:
        staging = Path(folder) / "delta"
        delta = create_database(staging, password=password)
        # Some pykeepass versions ship database-level settings in the blank template.
        # KeePassXC merges these settings independently of the entries.
        meta = delta.tree.find("Meta")
        for custom_data in meta.findall("CustomData"):
            meta.remove(custom_data)
        populate_delta(delta, base, updates)
        delta.save()
        staging.chmod(0o600)
        PyKeePass(staging, password=password)
        validate_output(args)
        if args.force:
            staging.replace(output)
        else:
            os.link(staging, output)


def convert_delta(args):
    previous, _ = read_snapshot(args.previous, "old CSV")
    incoming, compare_otp = read_snapshot(args.input, "new CSV")
    candidates, reviews = compare_snapshots(previous, incoming, compare_otp)
    if not args.dry_run:
        validate_output(args)

    password = os.environ.get(BASE_PASSWORD)
    if password is None:
        password = getpass("Master password for the current KeePassXC database: ")
    try:
        base = PyKeePass(args.base, password=password or None, keyfile=args.base_keyfile)
    except Exception:
        raise DeltaError("Could not open the current KeePassXC database") from None

    updates, already_applied = plan_delta(base, candidates, reviews)
    additions = sum(update.current is None for update in updates)
    for review in reviews:
        review.report()
    print(f"Delta plan has {additions} added, {len(updates) - additions} updated, "
          f"{already_applied} already applied and {len(reviews)} review items")
    if updates and not args.dry_run:
        try:
            write_delta(args, base, updates)
        except DeltaError:
            raise
        except Exception:
            raise DeltaError("Could not create or verify the delta database") from None
        print(f"Verified delta database written to {args.output}")
    else:
        print("No delta database written")
    return 2 if reviews else 0


def main():
    args = parse_args()
    if args.previous:
        try:
            return convert_delta(args)
        except (DeltaError, OSError) as error:
            message = str(error) if isinstance(error, DeltaError) else "Could not access a delta file"
            print(f"ERROR: {message}", file=sys.stderr)
            return 1
    convert(args)


if __name__ == "__main__":
    sys.exit(main())
