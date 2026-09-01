#!/usr/bin/env python3
"""Retina wallpaper filters for sync-astronomy-wallpapers.py."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[2] / "sync-astronomy-wallpapers.py"
spec = importlib.util.spec_from_file_location("saw", SCRIPT)
saw = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(saw)

NATIVE_W = 3456
NATIVE_H = 2234
MAX_MIB = 64


def write_jpeg(path: Path, width: int, height: int, nbytes: int) -> None:
    sof = bytes(
        [
            0xFF,
            0xC0,
            0x00,
            0x0B,
            0x08,
            (height >> 8) & 0xFF,
            height & 0xFF,
            (width >> 8) & 0xFF,
            width & 0xFF,
            0x01,
            0x01,
            0x11,
            0x00,
        ]
    )
    data = b"\xff\xd8" + sof + b"\xff\xd9"
    if nbytes < len(data):
        raise ValueError("nbytes too small for JPEG header")
    path.write_bytes(data + b"\x00" * (nbytes - len(data)))


def select_defaults(src: Path, max_bytes: int | None = None):
    return saw.select(
        src,
        100,
        saw.MAX_BYTES if max_bytes is None else max_bytes,
        saw.MIN_WIDTH,
        min_height=saw.MIN_HEIGHT,
    )


class TestRetinaWallpaperDefaults(unittest.TestCase):
    def test_defaults_match_16inch_retina(self):
        self.assertEqual(saw.MIN_WIDTH, NATIVE_W)
        self.assertEqual(saw.MIN_HEIGHT, NATIVE_H)
        self.assertEqual(saw.MAX_BYTES, MAX_MIB * 1024 * 1024)

    def test_parse_args_exposes_min_height(self):
        with patch.object(sys, "argv", ["sync-astronomy-wallpapers.py"]):
            args = saw.parse_args()
        self.assertEqual(args.min_width, NATIVE_W)
        self.assertEqual(args.min_height, NATIVE_H)
        self.assertEqual(args.max_bytes, MAX_MIB * 1024 * 1024)


class TestSelectRetinaFilter(unittest.TestCase):
    def test_keeps_native_landscape(self):
        with tempfile.TemporaryDirectory() as td:
            src = Path(td)
            write_jpeg(src / "ok.jpg", NATIVE_W, NATIVE_H, 2000)
            names, stats = select_defaults(src)
            self.assertEqual(names, ["ok.jpg"])
            self.assertEqual(stats["ok"], 1)
            self.assertEqual(stats["skip_narrow"], 0)
            self.assertEqual(stats["skip_short"], 0)

    def test_skips_width_below_native(self):
        with tempfile.TemporaryDirectory() as td:
            src = Path(td)
            write_jpeg(src / "hd.jpg", 1920, 1080, 2000)
            names, stats = select_defaults(src)
            self.assertEqual(names, [])
            self.assertEqual(stats["skip_narrow"], 1)

    def test_skips_height_below_native(self):
        with tempfile.TemporaryDirectory() as td:
            src = Path(td)
            write_jpeg(src / "wide-short.jpg", 4000, 2000, 2000)
            names, stats = select_defaults(src)
            self.assertEqual(names, [])
            self.assertEqual(stats["skip_short"], 1)

    def test_skips_4k_16x9_as_too_short(self):
        with tempfile.TemporaryDirectory() as td:
            src = Path(td)
            write_jpeg(src / "4k.jpg", 3840, 2160, 2000)
            names, stats = select_defaults(src)
            self.assertEqual(names, [])
            self.assertEqual(stats["skip_short"], 1)

    def test_keeps_larger_than_native(self):
        with tempfile.TemporaryDirectory() as td:
            src = Path(td)
            write_jpeg(src / "big.jpg", 4000, 3000, 2000)
            names, stats = select_defaults(src)
            self.assertEqual(names, ["big.jpg"])
            self.assertEqual(stats["ok"], 1)

    def test_skips_portrait_even_when_tall_enough(self):
        with tempfile.TemporaryDirectory() as td:
            src = Path(td)
            write_jpeg(src / "port.jpg", 4000, 5000, 2000)
            names, stats = select_defaults(src)
            self.assertEqual(names, [])
            self.assertEqual(stats["skip_portrait"], 1)

    def test_keeps_file_between_old_and_new_max_bytes(self):
        with tempfile.TemporaryDirectory() as td:
            src = Path(td)
            old_max = 10 * 1024 * 1024
            size = old_max + 1024
            write_jpeg(src / "large.jpg", NATIVE_W, NATIVE_H, size)
            names, stats = select_defaults(src)
            self.assertEqual(names, ["large.jpg"])
            self.assertEqual(stats["ok"], 1)
            self.assertEqual(stats["skip_size"], 0)


if __name__ == "__main__":
    unittest.main()
