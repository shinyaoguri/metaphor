#!/usr/bin/env python3
"""Unit tests for scripts/shots_common.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

チュートリアル（generate-tutorial-shots.py）と Examples（generate-example-shots.py）が
共有する部分だけをここで確かめる。確かめるのは 4 つ — **台帳に入れる実寸をヘッダから
読めること**、**撮影時のソースの指紋が「絵を変えうる変更」だけで動くこと**、
**撮影時の来歴とそこから数える実装の隔たり**、**入力台本の読み取り規則**。指紋は
どちらのスクリプトでも「コードを変えたのに画像が古い」を検出する土台なので、ここが
壊れると両方の `--check` が同時に嘘をつく。来歴は指紋が拾えないライブラリ実装の変更を
あとから言うためのもので、リファレンス（generate-reference-shots.py）もこれを使う
（#586）。台本は入力が要るスケッチを撮る唯一の経路で、こちらも両スクリプトが同じ
実装を使う（#610）。
"""

import importlib.util
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

from _git_helpers import git as hermetic_git, init_repo

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

    def test_gif_reads_the_logical_screen(self) -> None:
        # DocC リファレンスの動きは GIF になる（WebP を無言で落とすため。ADR-0008）。
        path = self.root / "shot.gif"
        path.write_bytes(
            b"GIF89a" + (480).to_bytes(2, "little") + (360).to_bytes(2, "little") + b"\x00" * 8
        )
        self.assertEqual(common.image_size(path), (480, 360))

    def test_an_unknown_format_is_an_error(self) -> None:
        path = self.root / "shot.png"
        path.write_bytes(b"\xff\xd8\xff\xe0" + b"\x00" * 20)  # JPEG（未対応）
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

    def test_excluded_output_does_not_change_the_hash(self) -> None:
        # 出力（実行結果画像）をパッケージ直下に置く Examples 向け。材料に入れると
        # 画像を差し替えただけで「ソースが変わった」になる（#820）。
        package = self.package()
        image = package / "Sketch.png"
        image.write_bytes(b"\x89PNG\r\n\x1a\nold")
        before = common.source_hash(package, exclude=[image])
        image.write_bytes(b"\x89PNG\r\n\x1a\nnew")
        self.assertEqual(common.source_hash(package, exclude=[image]), before)
        # 外していないファイルは従来どおり材料に入る（守備範囲は狭めない）。
        self.assertNotEqual(common.source_hash(package), before)

    def test_excluding_a_path_that_is_not_there_is_harmless(self) -> None:
        # 呼び出し側は出力の置き場を知っていればよく、有無は問わない。
        package = self.package()
        self.assertEqual(
            common.source_hash(package, exclude=[package / "Sketch.png"]),
            common.source_hash(package),
        )

    def test_renaming_a_file_changes_the_hash(self) -> None:
        # 中身が同じでも構成が変われば絵は変わりうる（パス名も材料に入れている）。
        package = self.package()
        before = common.source_hash(package)
        (package / "Sketch/App.swift").rename(package / "Sketch/Main.swift")
        self.assertNotEqual(common.source_hash(package), before)


class GitTestCase(CommonTestCase):
    """来歴の検査は git の履歴を要るので、使い捨てのリポジトリを 1 つ作る。"""

    def setUp(self) -> None:
        super().setUp()
        self.repo = init_repo(self.root / "repo")
        (self.repo / "Sources").mkdir(parents=True)
        (self.repo / "docs").mkdir()
        common.implementation_drift.cache_clear()
        self.addCleanup(common.implementation_drift.cache_clear)

    def git(self, *args: str) -> str:
        """開発機のグローバル設定から密封して git を引く（#979）。"""
        return hermetic_git(*args, cwd=self.repo).strip()

    def commit(self, path: str, text: str) -> str:
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", f"touch {path}")
        return self.git("rev-parse", "HEAD")


class TestCaptureProvenance(GitTestCase):
    """撮った実装を台帳に残す（指紋が拾えないライブラリ変更の手がかり。#586）。"""

    def test_it_records_the_current_commit(self) -> None:
        head = self.commit("Sources/Draw.swift", "func draw() {}\n")
        self.assertEqual(
            common.capture_provenance(self.repo), {"commit": head, "dirty": False}
        )

    def test_uncommitted_sources_are_recorded_as_dirty(self) -> None:
        # 直している最中に撮ることは普通にある。commit だけでは実装を特定できない。
        self.commit("Sources/Draw.swift", "func draw() {}\n")
        (self.repo / "Sources/Draw.swift").write_text("func draw() { circle() }\n")
        provenance = common.capture_provenance(self.repo)
        self.assertTrue(provenance["dirty"])

    def test_changes_outside_sources_are_not_dirty(self) -> None:
        self.commit("Sources/Draw.swift", "func draw() {}\n")
        (self.repo / "docs/note.md").write_text("編集中\n")
        self.assertFalse(common.capture_provenance(self.repo)["dirty"])

    def test_a_directory_without_git_records_nothing(self) -> None:
        # git が引けない環境でも撮影は続けられる必要がある。
        self.assertIsNone(common.capture_provenance(self.root / "not-a-repo"))


class TestImplementationDrift(GitTestCase):
    """撮影時の commit から HEAD までに Sources/ が何回変わったか。"""

    def test_no_change_since_the_shot(self) -> None:
        head = self.commit("Sources/Draw.swift", "func draw() {}\n")
        self.assertEqual(common.implementation_drift(head, self.repo), 0)

    def test_it_counts_commits_that_touched_sources(self) -> None:
        shot = self.commit("Sources/Draw.swift", "func draw() {}\n")
        self.commit("Sources/Draw.swift", "func draw() { circle() }\n")
        self.commit("Sources/Style.swift", "func fill() {}\n")
        self.assertEqual(common.implementation_drift(shot, self.repo), 2)

    def test_changes_outside_sources_are_not_counted(self) -> None:
        # ドキュメントだけの PR で全点が「実装が変わった」と言われては困る。
        shot = self.commit("Sources/Draw.swift", "func draw() {}\n")
        self.commit("docs/note.md", "書き足し\n")
        self.assertEqual(common.implementation_drift(shot, self.repo), 0)

    def test_an_unknown_commit_is_unknown_not_zero(self) -> None:
        # 浅い clone・未 push のローカル commit。「変わっていない」と混同しない。
        self.commit("Sources/Draw.swift", "func draw() {}\n")
        self.assertIsNone(common.implementation_drift("0" * 40, self.repo))


class TestDriftSummary(GitTestCase):
    """点ごとに 300 行出さず、要約 1 本にまとめる（#586）。"""

    def summary(self, entries: list[dict | None]) -> list[str]:
        return common.drift_summary(entries, "スケッチと撮影設定", self.repo)

    def test_nothing_to_say_when_every_shot_is_current(self) -> None:
        head = self.commit("Sources/Draw.swift", "func draw() {}\n")
        entry = {"provenance": {"commit": head, "dirty": False}}
        self.assertEqual(self.summary([entry, entry]), [])

    def test_it_counts_shots_taken_before_a_source_change(self) -> None:
        shot = self.commit("Sources/Draw.swift", "func draw() {}\n")
        self.commit("Sources/Draw.swift", "func draw() { circle() }\n")
        lines = self.summary([{"provenance": {"commit": shot, "dirty": False}}])
        self.assertIn("1 点は撮影後に Sources/ が変わっている（最大 1 コミット）", lines[0])

    def test_entries_without_provenance_are_unknown(self) -> None:
        # 既存の画像には来歴が無い。撮り直せば入る（遡って埋めはしない）。
        lines = self.summary([{"sourceHash": "abc"}])
        self.assertIn("1 点は撮影時の来歴が未記録", lines[0])

    def test_a_dirty_shot_is_called_out(self) -> None:
        head = self.commit("Sources/Draw.swift", "func draw() {}\n")
        self.commit("Sources/Draw.swift", "func draw() { circle() }\n")
        lines = self.summary([{"provenance": {"commit": head, "dirty": True}}])
        self.assertTrue(any("未コミットの変更がある状態で撮られている" in l for l in lines))

    def test_a_dirty_shot_is_reported_even_with_no_drift(self) -> None:
        # 隔たりが 0 でも、撮影時の実装は commit から復元できない。
        head = self.commit("Sources/Draw.swift", "func draw() {}\n")
        lines = self.summary([{"provenance": {"commit": head, "dirty": True}}])
        self.assertTrue(any("未コミットの変更がある状態で撮られている" in l for l in lines))

    def test_it_always_says_what_the_check_does_not_cover(self) -> None:
        lines = self.summary([{"sourceHash": "abc"}])
        self.assertIn("ライブラリ実装の変更は見ていない", lines[-1])


class TestInputScript(CommonTestCase):
    """撮影用の入力台本（`probe-input.jsonl`）の読み取り規則（#509）。"""

    def parse(self, text: str) -> list[dict]:
        return common.parse_input_script(text, "ref")

    def test_events_keep_their_order(self) -> None:
        events = self.parse(
            '{"t":"mouseMove","x":10,"y":20}\n{"t":"mouseDown","x":10,"y":20,"button":0}\n'
        )
        self.assertEqual([event["t"] for event in events], ["mouseMove", "mouseDown"])

    def test_wait_lines_are_kept_as_waits(self) -> None:
        events = self.parse('{"wait":250}\n{"t":"mouseUp","x":1,"y":2}\n')
        self.assertEqual(events[0], {"wait": 250})
        self.assertEqual(events[1]["t"], "mouseUp")

    def test_comments_and_blank_lines_are_ignored(self) -> None:
        events = self.parse('// 台本の意図\n\n{"t":"keyDown","code":49}\n')
        self.assertEqual(len(events), 1)

    def test_a_line_without_t_or_wait_is_an_error(self) -> None:
        with self.assertRaises(common.ShotError):
            self.parse('{"x":10,"y":20}\n')

    def test_a_negative_wait_is_an_error(self) -> None:
        with self.assertRaises(common.ShotError):
            self.parse('{"wait":-5}\n')

    def test_broken_json_is_an_error(self) -> None:
        with self.assertRaises(common.ShotError):
            self.parse('{"t":"mouseMove",\n')

    def test_a_script_without_events_is_an_error(self) -> None:
        with self.assertRaises(common.ShotError):
            self.parse("// 説明だけ\n\n")

    def test_missing_script_means_no_input(self) -> None:
        self.assertIsNone(common.load_input_script(self.root, "ref"))

    def test_script_is_read_from_the_package_root(self) -> None:
        (self.root / common.INPUT_SCRIPT_NAME).write_text(
            '{"t":"mouseMove","x":5,"y":6}\n', encoding="utf-8"
        )
        self.assertEqual(len(common.load_input_script(self.root, "ref") or []), 1)


if __name__ == "__main__":
    unittest.main()
