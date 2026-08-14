#!/usr/bin/env python3
"""Unit tests for scripts/shots_common.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

チュートリアル（generate-tutorial-shots.py）と Examples（generate-example-shots.py）が
共有する部分だけをここで確かめる。確かめるのは 2 つ — **台帳に入れる実寸をヘッダから
読めること**と、**撮影時のソースの指紋が「絵を変えうる変更」だけで動くこと**。
後者はどちらのスクリプトでも「コードを変えたのに画像が古い」を検出する土台なので、
ここが壊れると両方の `--check` が同時に嘘をつく。
"""

import importlib.util
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "shots_common.py"
_spec = importlib.util.spec_from_file_location("shots_common", _SCRIPT)
common = importlib.util.module_from_spec(_spec)
sys.modules["shots_common"] = common
_spec.loader.exec_module(common)


class CommonTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)


class TestImageSize(CommonTestCase):
    """台帳に入れる実寸をヘッダから読む（website がこれを本文へ焼き込む）。"""

    def png(self, width: int, height: int) -> Path:
        path = self.root / "shot.png"
        path.write_bytes(
            b"\x89PNG\r\n\x1a\n"
            + (13).to_bytes(4, "big")
            + b"IHDR"
            + width.to_bytes(4, "big")
            + height.to_bytes(4, "big")
        )
        return path

    def webp(self, chunk: bytes, payload: bytes) -> Path:
        path = self.root / "shot.webp"
        body = b"WEBP" + chunk + len(payload).to_bytes(4, "little") + payload
        path.write_bytes(b"RIFF" + len(body).to_bytes(4, "little") + body)
        return path

    def test_png(self) -> None:
        self.assertEqual(common.image_size(self.png(640, 360)), (640, 360))

    def test_animated_webp_reads_the_canvas(self) -> None:
        # 動きの証跡はこの形式（VP8X）。canvas は 1 始まりで 3 バイトずつ。
        payload = b"\x10\x00\x00\x00" + (639).to_bytes(3, "little") + (359).to_bytes(3, "little")
        self.assertEqual(common.image_size(self.webp(b"VP8X", payload)), (640, 360))

    def test_lossy_webp(self) -> None:
        payload = b"\x00" * 6 + (560).to_bytes(2, "little") + (315).to_bytes(2, "little")
        self.assertEqual(common.image_size(self.webp(b"VP8 ", payload)), (560, 315))

    def test_lossless_webp(self) -> None:
        bits = (640 - 1) | ((360 - 1) << 14)
        self.assertEqual(
            common.image_size(self.webp(b"VP8L", b"\x2f" + bits.to_bytes(4, "little"))),
            (640, 360),
        )

    def test_an_unknown_format_is_an_error(self) -> None:
        path = self.root / "shot.png"
        path.write_bytes(b"GIF89a" + b"\x00" * 20)
        with self.assertRaises(common.ShotError):
            common.image_size(path)


class TestSourceHash(CommonTestCase):
    """撮影時のソースの指紋。両方のスクリプトの `--check` がこれに乗っている。"""

    def package(self) -> Path:
        package = self.root / "Sketch"
        (package / "Sketch").mkdir(parents=True)
        (package / "Package.swift").write_text("// swift-tools-version: 5.10\n")
        (package / "Sketch/App.swift").write_text("func draw() {}\n")
        return package

    def test_the_same_tree_hashes_the_same(self) -> None:
        package = self.package()
        self.assertEqual(common.source_hash(package), common.source_hash(package))

    def test_changing_swift_changes_the_hash(self) -> None:
        package = self.package()
        before = common.source_hash(package)
        (package / "Sketch/App.swift").write_text("func draw() { circle(0, 0, 10) }\n")
        self.assertNotEqual(common.source_hash(package), before)

    def test_changing_a_resource_changes_the_hash(self) -> None:
        # Swift だけを見ていた頃は、同梱画像を差し替えても最新と答えていた（#505）。
        package = self.package()
        texture = package / "Sketch/Resources/texture.png"
        texture.parent.mkdir()
        texture.write_bytes(b"\x89PNG\r\n\x1a\nold")
        before = common.source_hash(package)
        texture.write_bytes(b"\x89PNG\r\n\x1a\nnew")
        self.assertNotEqual(common.source_hash(package), before)

    def test_build_artifacts_do_not_change_the_hash(self) -> None:
        # .build などは絵に影響しないので、混ぜると常に stale になってしまう。
        package = self.package()
        before = common.source_hash(package)
        for name in (".build", ".swiftpm", ".metaphor"):
            noise = package / name / "noise.txt"
            noise.parent.mkdir()
            noise.write_text("artifact")
        (package / ".DS_Store").write_bytes(b"\x00")
        self.assertEqual(common.source_hash(package), before)

    def test_renaming_a_file_changes_the_hash(self) -> None:
        # 中身が同じでも構成が変われば絵は変わりうる（パス名も材料に入れている）。
        package = self.package()
        before = common.source_hash(package)
        (package / "Sketch/App.swift").rename(package / "Sketch/Main.swift")
        self.assertNotEqual(common.source_hash(package), before)


if __name__ == "__main__":
    unittest.main()
