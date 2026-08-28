#!/usr/bin/env python3
"""Compare project archives with their live directories, content only.

Default is report-only. Pass --remove to delete the live directory after
a full match (same file set, same bytes, same symlink targets).

An archive matches a live directory when they sit next to each other:
  parent/name.tgz              <->  parent/name/
  parent/name_YYYYMMDD.tgz     <->  parent/name/

Usage:
  verify_project_archives.py [options] ARCHIVE.tgz [ARCHIVE.tgz ...]
  verify_project_archives.py --scan ROOT
  verify_project_archives.py --from-list FILE
  verify_project_archives.py ARCHIVE.tgz --live DIR
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
import tarfile
from pathlib import Path


BUF = 1024 * 1024
ARCHIVE_SUFFIXES = (".tar.gz", ".tgz", ".tar.bz2", ".tar.xz", ".tar")
DATE_SUFFIX = re.compile(r"_\d{8}$")


def equal_bytes(a_file, disk_path: Path) -> bool:
    with disk_path.open("rb") as disk:
        while True:
            chunk_a = a_file.read(BUF)
            chunk_d = disk.read(BUF)
            if chunk_a != chunk_d:
                return False
            if not chunk_a:
                return True


def strip_archive_suffix(name: str) -> str | None:
    for ext in ARCHIVE_SUFFIXES:
        if name.endswith(ext):
            return name[: -len(ext)]
    return None


def live_stem(archive_name: str) -> str | None:
    stem = strip_archive_suffix(archive_name)
    if not stem:
        return None
    return DATE_SUFFIX.sub("", stem)


def live_dir_for(tgz: Path, live: Path | None = None) -> Path | None:
    if live is not None:
        return live if live.is_dir() else None
    raw = strip_archive_suffix(tgz.name)
    if not raw:
        return None
    candidates = [raw]
    stripped = DATE_SUFFIX.sub("", raw)
    if stripped and stripped not in candidates:
        candidates.append(stripped)
    for stem in candidates:
        candidate = tgz.with_name(stem)
        if candidate.is_dir():
            return candidate
    return None


def collect_disk(live: Path) -> dict[str, str]:
    """Map archive-style names (parent/base/...) to kind: file|dir|symlink."""
    parent = live.parent
    entries: dict[str, str] = {}
    entries[live.relative_to(parent).as_posix()] = "dir"
    for root, dirs, files in os.walk(live, followlinks=False):
        root_path = Path(root)
        for d in dirs:
            p = root_path / d
            rel = p.relative_to(parent).as_posix()
            if p.is_symlink():
                entries[rel] = "symlink"
            else:
                entries[rel] = "dir"
        for f in files:
            p = root_path / f
            rel = p.relative_to(parent).as_posix()
            if p.is_symlink():
                entries[rel] = "symlink"
            elif p.is_file():
                entries[rel] = "file"
            else:
                entries[rel] = "other"
    return entries


def member_name(info: tarfile.TarInfo) -> str:
    name = info.name.strip()
    if name.startswith("./"):
        name = name[2:]
    return name.rstrip("/")


def verify_one(
    tgz: Path, max_issues: int, live: Path | None = None
) -> tuple[bool, list[str], dict[str, int], Path | None]:
    live_dir = live_dir_for(tgz, live)
    issues: list[str] = []
    stats = {
        "archive_files": 0,
        "compared": 0,
        "missing_on_disk": 0,
        "content_diff": 0,
        "type_diff": 0,
        "symlink_diff": 0,
        "unread_disk": 0,
        "extra_on_disk": 0,
        "unread_archive": 0,
    }
    if live_dir is None:
        return False, [f"no live directory next to {tgz}"], stats, None

    disk = collect_disk(live_dir)
    seen: set[str] = set()

    try:
        tar = tarfile.open(tgz, "r:*")
    except (tarfile.TarError, OSError) as exc:
        return False, [f"unreadable archive: {exc}"], stats, live_dir

    with tar:
        for info in tar:
            name = member_name(info)
            if not name:
                continue
            seen.add(name)
            disk_kind = disk.get(name)
            disk_path = live_dir.parent / name

            if info.isdir():
                if disk_kind is None:
                    issues.append(f"MISSING_ON_DISK dir {name}")
                    stats["missing_on_disk"] += 1
                elif disk_kind != "dir":
                    issues.append(f"TYPE {name}: archive=dir disk={disk_kind}")
                    stats["type_diff"] += 1
                continue

            if info.issym() or info.islnk():
                stats["archive_files"] += 1
                if disk_kind is None:
                    issues.append(f"MISSING_ON_DISK link {name}")
                    stats["missing_on_disk"] += 1
                    continue
                if not disk_path.is_symlink() and not info.islnk():
                    issues.append(f"TYPE {name}: archive=link disk={disk_kind}")
                    stats["type_diff"] += 1
                    continue
                try:
                    target = os.readlink(disk_path)
                except OSError as exc:
                    issues.append(f"UNREAD_DISK {name}: {exc}")
                    stats["unread_disk"] += 1
                    continue
                if info.issym() and target != info.linkname:
                    issues.append(
                        f"SYMLINK {name}: archive={info.linkname!r} disk={target!r}"
                    )
                    stats["symlink_diff"] += 1
                continue

            if not info.isfile():
                continue

            stats["archive_files"] += 1
            if disk_kind is None:
                issues.append(f"MISSING_ON_DISK file {name}")
                stats["missing_on_disk"] += 1
                continue
            if disk_kind != "file":
                issues.append(f"TYPE {name}: archive=file disk={disk_kind}")
                stats["type_diff"] += 1
                continue

            extracted = tar.extractfile(info)
            if extracted is None:
                issues.append(f"UNREAD_ARCHIVE {name}")
                stats["unread_archive"] += 1
                continue
            try:
                try:
                    same = equal_bytes(extracted, disk_path)
                except OSError as exc:
                    issues.append(f"UNREAD_DISK {name}: {exc}")
                    stats["unread_disk"] += 1
                    continue
            finally:
                extracted.close()

            stats["compared"] += 1
            if not same:
                issues.append(f"CONTENT {name}")
                stats["content_diff"] += 1

    extras = sorted(set(disk) - seen)
    for name in extras:
        issues.append(f"EXTRA_ON_DISK {disk[name]} {name}")
        stats["extra_on_disk"] += 1

    ok = not issues
    if len(issues) > max_issues:
        hidden = len(issues) - max_issues
        issues = issues[:max_issues] + [f"... {hidden} more"]
    return ok, issues, stats, live_dir


def is_archive_name(name: str) -> bool:
    return strip_archive_suffix(name) is not None


def find_archives(root: Path) -> list[Path]:
    found: list[Path] = []
    skip_dirs = {".git", "node_modules", ".hg", ".svn", "__pycache__", ".venv"}
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        dirnames[:] = [d for d in dirnames if d not in skip_dirs]
        for name in filenames:
            if not is_archive_name(name):
                continue
            tgz = Path(dirpath) / name
            if live_dir_for(tgz) is not None:
                found.append(tgz)
    return sorted(found)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compare project archives with live directories (content only)."
    )
    parser.add_argument("archives", nargs="*", type=Path, help="Archive files to check")
    parser.add_argument(
        "--remove",
        action="store_true",
        help="Delete the live directory after a full content match",
    )
    parser.add_argument(
        "--scan",
        type=Path,
        help="Find sibling archive/dir pairs under this directory",
    )
    parser.add_argument(
        "--from-list",
        type=Path,
        help="File with one archive path per line",
    )
    parser.add_argument(
        "--live",
        type=Path,
        help="Live directory for a single archive (when it is not a sibling)",
    )
    parser.add_argument(
        "--max-issues",
        type=int,
        default=30,
        help="Print at most N issue paths per archive (default 30)",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Print only RESULT lines and the SUMMARY",
    )
    args = parser.parse_args()

    if args.live is not None and len(args.archives) != 1:
        parser.error("--live requires exactly one ARCHIVE.tgz")

    archives: list[Path] = []
    if args.from_list:
        for line in args.from_list.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                archives.append(Path(line))
    if args.scan:
        archives.extend(find_archives(args.scan))
    archives.extend(args.archives)

    if not archives and args.scan is None and args.from_list is None:
        archives.extend(find_archives(Path.cwd()))

    if not archives:
        print(
            "No archives given. Pass files, --scan ROOT, or --from-list FILE.",
            file=sys.stderr,
        )
        return 2

    seen_paths: set[Path] = set()
    unique: list[Path] = []
    for path in archives:
        path = path.resolve()
        if path in seen_paths:
            continue
        seen_paths.add(path)
        unique.append(path)

    live_override = args.live.resolve() if args.live is not None else None
    matched = 0
    failed = 0
    removed = 0
    rc = 0

    for tgz in unique:
        live_arg = live_override if live_override is not None else None
        preview = live_dir_for(tgz, live_arg)
        if not args.quiet:
            print(f"ARCHIVE {tgz}")
            print(f"LIVE    {preview if preview else '-'}")
        if not tgz.is_file():
            print("RESULT  FAIL missing archive")
            if not args.quiet:
                print()
            failed += 1
            rc = 1
            continue
        ok, issues, stats, live_dir = verify_one(tgz, args.max_issues, live_arg)
        if not args.quiet:
            print(
                "STATS   archive_files={archive_files} compared={compared} "
                "missing_on_disk={missing_on_disk} extra_on_disk={extra_on_disk} "
                "content_diff={content_diff} type_diff={type_diff} "
                "symlink_diff={symlink_diff} unread_disk={unread_disk} "
                "unread_archive={unread_archive}".format(**stats)
            )
        if ok:
            print("RESULT  MATCH content matches")
            matched += 1
            if args.remove and live_dir is not None:
                shutil.rmtree(live_dir)
                print(f"REMOVED {live_dir}")
                removed += 1
        else:
            print("RESULT  FAIL")
            if not args.quiet:
                for issue in issues:
                    print(f"  {issue}")
            failed += 1
            rc = 1
        if not args.quiet:
            print()

    print(
        f"SUMMARY archives={len(unique)} match={matched} fail={failed} removed={removed}"
    )
    return rc


if __name__ == "__main__":
    sys.exit(main())
