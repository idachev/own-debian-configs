#!/usr/bin/env python3
"""
Mirror a directory tree into another one, packing selected directories into
one .zip each. Files that are not inside a packed directory are hard linked
(or copied, when a hard link is not possible) to the same relative path.

Useful before uploading a tree with many small files (e.g. scanned pages) to
a service that is slow per file, such as Google Drive.

Zips use no compression (the typical content, JPG/PNG/PDF, is already
compressed) and store names as UTF-8, so non-Latin names open correctly on
macOS, Linux and Windows. Each zip contains the directory itself as its top
entry, so unpacking gives back the original folder.

A zip is skipped when it already exists and is newer than every file in its
directory, so the script can be run again after the source tree grows.

Usage:
    zip_dirs_tree.py <src_dir> <dest_dir> [--unit GLOB ...] [--jobs N] [--force]

Arguments:
    src_dir   - Source tree
    dest_dir  - Output tree (created when missing)
    --unit    - Glob relative to src_dir that selects directories to pack.
                Repeat for several levels. Default: '*' (every top-level dir).
                When a directory and one of its parents both match, only the
                parent is packed.
    --jobs    - Parallel zip workers (default: 4)
    --force   - Rebuild zips even when they look up to date
    --dry-run - Print what would be done

Examples:
    zip_dirs_tree.py ./books ./books-zips
    zip_dirs_tree.py ./scans ./scans-zips --unit 'publisher-a/*' --unit 'publisher-b/*/*'
"""

import argparse
import os
import shutil
import sys
import zipfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

SKIP_NAMES = {".DS_Store", "Thumbs.db"}


def find_units(src, patterns):
    matched = sorted({p for pat in patterns for p in src.glob(pat) if p.is_dir()})
    units = []
    for p in matched:
        if not any(u in p.parents for u in units):
            units.append(p)
    return units


def iter_files(directory):
    for root, dirs, files in os.walk(directory):
        dirs.sort()
        for name in sorted(files):
            if name not in SKIP_NAMES:
                yield Path(root) / name


def zip_is_fresh(zip_path, unit):
    if not zip_path.exists():
        return False
    zip_mtime = zip_path.stat().st_mtime
    # Directory mtimes catch files that were added, removed or renamed.
    dirs = (Path(root) for root, _, _ in os.walk(unit))
    return all(p.stat().st_mtime <= zip_mtime
               for p in [*dirs, *iter_files(unit)])


def pack_unit(unit, zip_path):
    zip_path.parent.mkdir(parents=True, exist_ok=True)
    part = zip_path.with_name(zip_path.name + ".part")
    base = unit.parent
    count = 0
    try:
        # strict_timestamps=False clamps pre-1980 mtimes instead of failing.
        with zipfile.ZipFile(part, "w", zipfile.ZIP_STORED, allowZip64=True,
                             strict_timestamps=False) as z:
            for f in iter_files(unit):
                z.write(f, f.relative_to(base).as_posix())
                count += 1
    except BaseException:
        part.unlink(missing_ok=True)
        raise
    part.replace(zip_path)
    return count


def link_or_copy(src_file, dest_file):
    dest_file.parent.mkdir(parents=True, exist_ok=True)
    if dest_file.exists():
        s, d = src_file.stat(), dest_file.stat()
        if (s.st_ino, s.st_dev) == (d.st_ino, d.st_dev) or (
                s.st_size == d.st_size and int(s.st_mtime) == int(d.st_mtime)):
            return False
        dest_file.unlink()
    try:
        os.link(src_file, dest_file)
    except OSError:
        shutil.copy2(src_file, dest_file)
    return True


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("src_dir")
    parser.add_argument("dest_dir")
    parser.add_argument("--unit", action="append", default=None)
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    src = Path(args.src_dir).resolve()
    dest = Path(args.dest_dir).resolve()
    if not src.is_dir():
        sys.exit(f"Not a directory: {src}")
    if dest == src or src in dest.parents:
        sys.exit("dest_dir must be outside src_dir")

    units = find_units(src, args.unit or ["*"])
    unit_set = set(units)

    loose = [f for f in iter_files(src)
             if not any(p in unit_set for p in f.parents)]

    todo = []
    for u in units:
        zip_path = dest / (u.relative_to(src).as_posix() + ".zip")
        if args.force or not zip_is_fresh(zip_path, u):
            todo.append((u, zip_path))

    print(f"units: {len(units)}, to pack: {len(todo)}, loose files: {len(loose)}")
    if args.dry_run:
        for u, z in todo:
            print(f"zip  {u.relative_to(src)} -> {z.relative_to(dest)}")
        for f in loose:
            print(f"file {f.relative_to(src)}")
        return

    errors = 0
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {pool.submit(pack_unit, u, z): u for u, z in todo}
        for i, fut in enumerate(as_completed(futures), 1):
            u = futures[fut]
            try:
                n = fut.result()
                print(f"[{i}/{len(todo)}] {u.relative_to(src)}: {n} files", flush=True)
            except Exception as e:
                errors += 1
                print(f"[{i}/{len(todo)}] ERROR {u.relative_to(src)}: {e}", file=sys.stderr, flush=True)

    linked = sum(link_or_copy(f, dest / f.relative_to(src)) for f in loose)
    print(f"loose files linked/copied: {linked}, unchanged: {len(loose) - linked}")

    if errors:
        sys.exit(f"{errors} unit(s) failed")


if __name__ == "__main__":
    main()
