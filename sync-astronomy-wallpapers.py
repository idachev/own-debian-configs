#!/usr/bin/env python3
"""Copy wallpaper-sized images from Dropbox Astronomy into ~/Pictures/Astronomy.

Dropbox File Provider: st_size is metadata (safe). st_blocks == 0 means
the bytes are not on disk — opening the file downloads the whole object.
This script never opens those. Dimensions are read only from JPEG/PNG
headers of already-local files (a few KB from SSD).

Filters (in order, cheap first):
  1. extension: jpg/jpeg/png
  2. size from stat() only: 1 MiB .. 64 MiB  (no cloud fetch)
  3. skip unhydrated files (st_blocks == 0) instead of opening them
  4. pixel size from JPEG/PNG header of already-local files
     (width >= 3456 and height >= 2234 — 16-inch Retina, no Fill upscale)
  5. skip portrait (height > width) — laptop wallpaper

Then rsync copies only the survivors. Destination extras are removed so
the wallpaper folder stays a filtered cache, not a second Dropbox.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

MIN_BYTES = 1 * 1024 * 1024
MAX_BYTES = 64 * 1024 * 1024
MIN_WIDTH = 3456
MIN_HEIGHT = 2234
IMAGE_EXT = {".jpg", ".jpeg", ".png"}
HEADER_CAP = 2 * 1024 * 1024  # stop parsing if SOF not found by then
SOF = frozenset(
    {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}
)
# SOI/EOI/TEM/SOS — SOS means image data follows; no SOF found in headers
SKIP_MARKERS = frozenset({0xD8, 0xD9, 0x01, 0xDA})


def jpeg_dimensions(path: Path) -> tuple[int, int] | None:
    with path.open("rb") as f:
        if f.read(2) != b"\xff\xd8":
            return None
        read = 2
        while read < HEADER_CAP:
            b = f.read(1)
            read += 1
            if not b:
                return None
            if b != b"\xff":
                continue
            while True:
                m = f.read(1)
                read += 1
                if not m:
                    return None
                if m != b"\xff":
                    marker = m[0]
                    break
            if marker in SKIP_MARKERS:
                return None
            if marker in (0xD0, 0xD1, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7):
                continue
            ln = f.read(2)
            read += 2
            if len(ln) < 2:
                return None
            seglen = int.from_bytes(ln, "big")
            if seglen < 2:
                return None
            payload_len = seglen - 2
            if marker in SOF:
                payload = f.read(min(payload_len, 16))
                read += len(payload)
                if len(payload) < 5:
                    return None
                height = int.from_bytes(payload[1:3], "big")
                width = int.from_bytes(payload[3:5], "big")
                if width == 0 or height == 0:
                    return None
                return width, height
            # Skip APPn / DHT / etc. Seek is local I/O on an already-hydrated file.
            remain = min(payload_len, HEADER_CAP - read)
            f.seek(remain, os.SEEK_CUR)
            read += remain
            if remain < payload_len:
                return None
    return None


def png_dimensions(path: Path) -> tuple[int, int] | None:
    with path.open("rb") as f:
        hdr = f.read(24)
    if len(hdr) < 24 or hdr[:8] != b"\x89PNG\r\n\x1a\n" or hdr[12:16] != b"IHDR":
        return None
    width = int.from_bytes(hdr[16:20], "big")
    height = int.from_bytes(hdr[20:24], "big")
    if width == 0 or height == 0:
        return None
    return width, height


def image_dimensions(path: Path) -> tuple[int, int] | None:
    ext = path.suffix.lower()
    try:
        if ext in {".jpg", ".jpeg"}:
            return jpeg_dimensions(path)
        if ext == ".png":
            return png_dimensions(path)
    except OSError:
        return None
    return None


def paths_overlap(a: Path, b: Path) -> bool:
    try:
        a.relative_to(b)
        return True
    except ValueError:
        pass
    try:
        b.relative_to(a)
        return True
    except ValueError:
        return False


def parse_args() -> argparse.Namespace:
    home = Path.home()
    p = argparse.ArgumentParser(
        description="Rsync wallpaper-worthy Astronomy images out of Dropbox."
    )
    p.add_argument(
        "--src",
        type=Path,
        default=home / "Dropbox/pics/Astronomy",
        help="source folder (default: ~/Dropbox/pics/Astronomy)",
    )
    p.add_argument(
        "--dst",
        type=Path,
        default=home / "Pictures/Astronomy",
        help="destination folder for Wallpaper (default: ~/Pictures/Astronomy)",
    )
    p.add_argument("--min-bytes", type=int, default=MIN_BYTES)
    p.add_argument("--max-bytes", type=int, default=MAX_BYTES)
    p.add_argument("--min-width", type=int, default=MIN_WIDTH)
    p.add_argument("--min-height", type=int, default=MIN_HEIGHT)
    p.add_argument(
        "-n",
        "--dry-run",
        action="store_true",
        help="filter and show rsync plan, do not copy or create dest",
    )
    p.add_argument(
        "--keep-extra",
        action="store_true",
        help="do not delete files in dest that are no longer selected",
    )
    p.add_argument(
        "--measure-unhydrated",
        action="store_true",
        help=(
            "read JPEG/PNG headers of size-matched online-only files so width "
            "and height can be filtered. File Provider downloads each whole "
            "file when opened."
        ),
    )
    return p.parse_args()


def select(
    src: Path,
    min_bytes: int,
    max_bytes: int,
    min_width: int,
    measure_unhydrated: bool = False,
    min_height: int = MIN_HEIGHT,
) -> tuple[list[str], dict[str, int]]:
    stats = {
        "seen": 0,
        "skip_ext": 0,
        "skip_size": 0,
        "skip_unhydrated": 0,
        "skip_narrow": 0,
        "skip_short": 0,
        "skip_portrait": 0,
        "skip_header": 0,
        "ok": 0,
        "ok_bytes": 0,
        "measured": 0,
        "measured_unhydrated": 0,
    }
    names: list[str] = []
    with os.scandir(src) as it:
        for ent in it:
            if not ent.is_file(follow_symlinks=False):
                continue
            name = ent.name
            if name.startswith("."):
                continue
            ext = Path(name).suffix.lower()
            stats["seen"] += 1
            if ext not in IMAGE_EXT:
                stats["skip_ext"] += 1
                continue
            try:
                st = ent.stat(follow_symlinks=False)
            except OSError:
                stats["skip_header"] += 1
                continue
            size = st.st_size
            # st_size is Dropbox/Finder metadata — does not fetch content.
            # st_blocks == 0 means online-only; opening it downloads the whole file.
            if size < min_bytes or size > max_bytes:
                stats["skip_size"] += 1
                continue
            unhydrated = st.st_blocks == 0
            if unhydrated and not measure_unhydrated:
                stats["skip_unhydrated"] += 1
                continue
            dim = image_dimensions(src / name)
            stats["measured"] += 1
            if unhydrated:
                stats["measured_unhydrated"] += 1
            if stats["measured"] % 50 == 0:
                print(
                    f"measured   {stats['measured']} size-matched "
                    f"({stats['measured_unhydrated']} were online-only)",
                    flush=True,
                )
            if dim is None:
                stats["skip_header"] += 1
                continue
            width, height = dim
            if width < min_width:
                stats["skip_narrow"] += 1
                continue
            if height < min_height:
                stats["skip_short"] += 1
                continue
            if height > width:
                stats["skip_portrait"] += 1
                continue
            names.append(name)
            stats["ok"] += 1
            stats["ok_bytes"] += size
    names.sort()
    return names, stats


def prune_dest(dst: Path, wanted: set[str], dry_run: bool) -> int:
    """Remove dest files that are not in the filtered set. Never touches src."""
    if not dst.is_dir():
        return 0
    removed = 0
    with os.scandir(dst) as it:
        for ent in it:
            if not ent.is_file(follow_symlinks=False):
                continue
            if ent.name in wanted or ent.name == ".DS_Store":
                continue
            if dry_run:
                print(f"would delete {ent.path}")
            else:
                os.unlink(ent.path)
            removed += 1
    return removed


def rsync_copy(
    src: Path, dst: Path, names: list[str], dry_run: bool, keep_extra: bool
) -> int:
    if not dry_run:
        dst.mkdir(parents=True, exist_ok=True)
    elif not dst.exists():
        print(f"dry-run    dest does not exist yet: {dst}")

    cmd = ["rsync", "-a", "--human-readable", "--stats"]
    if dry_run:
        cmd.append("--dry-run")
    list_path = None
    try:
        with tempfile.NamedTemporaryFile(
            "wb", prefix="astro-wall-", suffix=".lst", delete=False
        ) as tmp:
            tmp.write(b"\0".join(name.encode("utf-8", "surrogateescape") for name in names))
            if names:
                tmp.write(b"\0")
            list_path = tmp.name
        cmd.extend(
            ["--from0", "--files-from", list_path, f"{src}/", f"{dst}/"]
        )
        print("rsync", "-a", "--from0 --files-from <list>", f"{src}/", f"{dst}/")
        proc = subprocess.run(cmd)
        if proc.returncode != 0:
            return proc.returncode
    finally:
        if list_path:
            try:
                os.unlink(list_path)
            except OSError:
                pass
    if not keep_extra:
        n = prune_dest(dst, set(names), dry_run)
        print(f"pruned     {n} extra file(s) from dest")
    return 0


def main() -> int:
    args = parse_args()
    src = args.src.expanduser().resolve()
    dst = args.dst.expanduser().resolve()
    if not src.is_dir():
        print(f"source is not a directory: {src}", file=sys.stderr)
        return 2
    if paths_overlap(src, dst):
        print("refusing to rsync overlapping src/dst paths", file=sys.stderr)
        return 2
    if dst.exists() and not dst.is_dir():
        print(f"destination exists and is not a directory: {dst}", file=sys.stderr)
        return 2

    print(f"src        {src}")
    print(f"dst        {dst}")
    print(
        f"filter     {args.min_bytes / (1024 * 1024):.0f}–"
        f"{args.max_bytes / (1024 * 1024):.0f} MiB, "
        f"width >= {args.min_width}px, "
        f"height >= {args.min_height}px, landscape jpg/png"
    )
    if args.measure_unhydrated:
        print(
            "cloud      will open size-matched online-only files to read "
            "width and height (each download is the whole file)"
        )
    else:
        print("cloud      size from stat; skip st_blocks=0 (online-only), no header read")
    names, stats = select(
        src,
        args.min_bytes,
        args.max_bytes,
        args.min_width,
        measure_unhydrated=args.measure_unhydrated,
        min_height=args.min_height,
    )
    print(
        f"scanned    {stats['seen']}  size-skip {stats['skip_size']}  "
        f"unhydrated {stats['skip_unhydrated']}  "
        f"narrow {stats['skip_narrow']}  short {stats['skip_short']}  "
        f"portrait {stats['skip_portrait']}  "
        f"bad-header {stats['skip_header']}  other-ext {stats['skip_ext']}"
    )
    print(
        f"selected   {stats['ok']} files, {stats['ok_bytes'] / (1024 * 1024):.1f} MiB"
        + ("  (dry-run)" if args.dry_run else "")
    )
    if not names:
        if not args.keep_extra and dst.exists() and not args.dry_run:
            print("nothing selected; leaving dest untouched")
        return 0
    return rsync_copy(src, dst, names, args.dry_run, args.keep_extra)


if __name__ == "__main__":
    sys.exit(main())
