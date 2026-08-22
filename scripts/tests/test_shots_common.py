#!/usr/bin/env python3
"""Unit tests for scripts/shots_common.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

3 つの撮影スクリプト（tutorial / example / reference）が共有する部分をここで確かめる。

- **台帳に入れる実寸をヘッダから読めること**
- **撮影時のソースの指紋が「絵を変えうる変更」だけで動くこと** — 「コードを変えたのに
  画像が古い」を検出する土台。ここが壊れると全部の `--check` が同時に嘘をつく
- **撮影時の来歴とそこから数える実装の隔たり**（#586）
- **入力台本の読み取り規則**（#610）
- **Probe の応答の読み方** — `frame.json` を id 一致で見る（CONTRACT.md 契約点 4）。
  実装が分かれていると契約の解釈が分かれるので、ここが唯一の置き場
- **撮らない申告の読み取り**（#544）と **Gyazo への上げ口**（#1021）
"""

import contextlib
import importlib.util
import io
import json
import os
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


class TestCurrentFrame(CommonTestCase):
    """Probe の応答の読み方（CONTRACT.md 契約点 4 の consumer 規約）。

    3 スクリプトが各々実装を持っていた時期があり、cli 側が wire format を変えたときに
    1 つだけ直る形になっていた。ここが唯一の置き場になったので、契約の肝はここで守る。
    """

    def write_frame(self, body: str) -> None:
        (self.root / "frame.json").write_text(body, encoding="utf-8")

    def test_a_matching_id_is_the_answer(self) -> None:
        self.write_frame(json.dumps({"id": "req-1", "size": {"width": 4, "height": 3}}))
        answer = common.current_frame(self.root, "req-1")
        self.assertEqual((answer or {}).get("size"), {"width": 4, "height": 3})

    def test_a_different_id_is_not_the_answer(self) -> None:
        """契約の肝。**下見の応答を本番の応答と取り違えない**。

        ファイルの有無だけで見ると、下見で書かれた frame.json をそのまま本番の結果として
        拾ってしまう（撮りたかった絵ではなく、起動直後の絵が台帳へ入る）。
        """
        self.write_frame(json.dumps({"id": "warmup"}))
        self.assertIsNone(common.current_frame(self.root, "req-1"))

    def test_no_file_yet_is_not_an_error(self) -> None:
        self.assertIsNone(common.current_frame(self.root, "req-1"))

    def test_a_half_written_file_is_retried(self) -> None:
        """書き込み途中を読んだだけ。次のポーリングで見直せばよいので落とさない。"""
        self.write_frame('{"id": "req-1", ')
        self.assertIsNone(common.current_frame(self.root, "req-1"))

    def test_a_failure_response_still_counts_as_an_answer(self) -> None:
        """失敗応答は `frame.json` だけが書かれる（契約点 4）。

        ここで None を返すと、撮影が失敗しているのにポーリングが続いてタイムアウトまで
        待つことになる。応答として返し、PNG が無いことは呼び出し側が見る。
        """
        self.write_frame(json.dumps({"id": "req-1", "warnings": ["no staging texture"]}))
        answer = common.current_frame(self.root, "req-1")
        self.assertEqual((answer or {}).get("warnings"), ["no staging texture"])


class TestNoCaptureReason(CommonTestCase):
    """撮らない申告（#544）。"""

    def write_marker(self, body: str) -> None:
        (self.root / common.NO_CAPTURE_NAME).write_text(body, encoding="utf-8")

    def test_the_written_reason_comes_back(self) -> None:
        self.write_marker("カメラの映像は撮る場所で変わる\n")
        self.assertEqual(
            common.no_capture_reason(self.root, "07-Media/03-Camera"),
            "カメラの映像は撮る場所で変わる",
        )

    def test_several_lines_are_joined(self) -> None:
        self.write_marker("マイク入力は環境で決まる。\n無音だと何も動かない。\n")
        self.assertEqual(
            common.no_capture_reason(self.root, "07-Media/01-AudioInput"),
            "マイク入力は環境で決まる。 無音だと何も動かない。",
        )

    def test_no_marker_means_capture_it(self) -> None:
        self.assertIsNone(common.no_capture_reason(self.root, "01-Getting/01-First"))

    def test_an_empty_marker_is_rejected(self) -> None:
        """理由を書かせること自体が申告の目的。空だと撮り忘れと見分けが付かない。"""
        self.write_marker("\n   \n")
        with self.assertRaises(common.ShotError):
            common.no_capture_reason(self.root, "07-Media/03-Camera")


class TestRunCapturing(CommonTestCase):
    """外部コマンドの実行。失敗は必ず `ShotError` にして、出力を添える。"""

    def test_stdout_comes_back_on_success(self) -> None:
        self.assertEqual(common.run_capturing(["echo", "done"], "確認"), "done\n")

    def test_a_failure_carries_the_output(self) -> None:
        with self.assertRaises(common.ShotError) as caught:
            common.run_capturing(["sh", "-c", "echo なにか >&2; exit 3"], "ビルド")
        message = str(caught.exception)
        self.assertIn("ビルド", message)
        self.assertIn("なにか", message)

    def test_run_or_raise_is_the_same_check(self) -> None:
        self.assertIsNone(common.run_or_raise(["true"], "確認"))
        with self.assertRaises(common.ShotError):
            common.run_or_raise(["false"], "確認")


STILL_URL = "https://i.gyazo.com/1111111111111111111111111111aaaa.png"
MOTION_URL = "https://i.gyazo.com/2222222222222222222222222222bbbb.webp"


class TestGyazoResponse(CommonTestCase):
    """Upload API の応答の検証（形式が変換されたら黙って進めない）。"""

    def test_url_is_taken_from_the_response(self) -> None:
        body = json.dumps({"url": STILL_URL, "type": "png"})
        self.assertEqual(common.gyazo_url_from_response(body, ".png"), STILL_URL)

    def test_animated_webp_keeps_its_extension(self) -> None:
        body = json.dumps({"url": MOTION_URL, "type": "webp"})
        self.assertEqual(common.gyazo_url_from_response(body, ".webp"), MOTION_URL)

    def test_a_converted_format_is_an_error(self) -> None:
        body = json.dumps({"url": STILL_URL, "type": "png"})
        with self.assertRaises(common.ShotError):
            common.gyazo_url_from_response(body, ".webp")

    def test_another_host_is_an_error(self) -> None:
        body = json.dumps({"url": "https://example.com/x.png"})
        with self.assertRaises(common.ShotError):
            common.gyazo_url_from_response(body, ".png")

    def test_an_error_response_is_reported(self) -> None:
        with self.assertRaises(common.ShotError):
            common.gyazo_url_from_response('{"message":"unauthorized"}', ".png")

    def test_a_non_json_response_is_reported(self) -> None:
        with self.assertRaises(common.ShotError):
            common.gyazo_url_from_response("<html>502</html>", ".png")


class TestGyazoToken(CommonTestCase):
    """トークンの読み口。

    正本は 1Password、読み口は `secret-read`（Keychain にキャッシュするラッパー）。
    **`secret-read` が居るのにそれを使わない**と、1Password のロックで無人の撮影が
    止まる — 実際に `op read` 直で 2 分ハングした。だからここは「どちらを選んだか」を
    見る。本物を呼ばずに済むよう、PATH の先頭に偽物を置いて差し替える。
    """

    def setUp(self) -> None:
        super().setUp()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "calls.log"
        # 読み取りは 1 プロセス 1 回のキャッシュなので、テストごとに剥がす
        common._GYAZO_TOKEN.clear()
        self.addCleanup(common._GYAZO_TOKEN.clear)
        self._path = os.environ.get("PATH", "")
        os.environ["PATH"] = f"{self.bin}:/usr/bin:/bin"
        self.addCleanup(os.environ.__setitem__, "PATH", self._path)

    def install(self, name: str, body: str) -> None:
        path = self.bin / name
        path.write_text(f"#!/bin/sh\nprintf '%s\\n' \"{name} $*\" >> {self.log}\n{body}\n")
        path.chmod(0o755)

    def calls(self) -> list[str]:
        if not self.log.exists():
            return []
        return [line for line in self.log.read_text().splitlines() if line]

    def test_secret_read_is_preferred(self) -> None:
        self.install("secret-read", "printf 'from-keychain\\n'")
        self.install("op", "printf 'from-1password\\n'")
        self.assertEqual(common.gyazo_token(), "from-keychain")
        self.assertEqual(len(self.calls()), 1, "op も呼んでいる")
        self.assertTrue(self.calls()[0].startswith("secret-read "))

    def test_op_is_the_fallback_and_says_so(self) -> None:
        self.install("op", "printf 'from-1password\\n'")
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            self.assertEqual(common.gyazo_token(), "from-1password")
        self.assertIn("secret-read", stderr.getvalue(), "黙って op に落ちている")

    def test_neither_reader_is_an_error(self) -> None:
        with self.assertRaises(common.ShotError):
            common.gyazo_token()

    def test_a_failing_reader_is_reported(self) -> None:
        self.install("secret-read", "echo 'item not found' >&2; exit 1")
        with self.assertRaises(common.ShotError):
            common.gyazo_token()

    def test_an_empty_value_is_an_error(self) -> None:
        """空文字を掴んだまま進むと、curl が意味の分からない失敗をする。"""
        self.install("secret-read", "printf '\\n'")
        with self.assertRaises(common.ShotError):
            common.gyazo_token()

    def test_the_value_is_read_only_once(self) -> None:
        self.install("secret-read", "printf 'from-keychain\\n'")
        common.gyazo_token()
        common.gyazo_token()
        self.assertEqual(len(self.calls()), 1, "呼ぶたびに読み直している")

    def test_the_error_never_carries_the_token(self) -> None:
        """エラー文に値を載せない（ログや Issue に貼られる先まで漏れる）。"""
        self.install("secret-read", "printf 'super-secret-token\\n'; exit 1")
        with self.assertRaises(common.ShotError) as caught:
            common.gyazo_token()
        self.assertNotIn("super-secret-token", str(caught.exception))


class TestUploadCommand(CommonTestCase):
    """curl へ渡す組み立て。

    ここを実際に走らせて確かめると Gyazo にテスト用の画像が積み上がる（アセットは
    不変・追記型なので消せない）ので、ネットワークには出ず**組み立てだけ**を見る。
    """

    def setUp(self) -> None:
        super().setUp()
        common._GYAZO_TOKEN.clear()
        common._GYAZO_TOKEN.append("token-abc")
        self.addCleanup(common._GYAZO_TOKEN.clear)
        self.path = self.root / "shot.png"
        self.path.write_bytes(b"\x89PNG\r\n\x1a\n")
        self.commands: list[list[str]] = []

    def fake_run(self, returncode: int = 0, stdout: str = "") -> None:
        class Result:
            pass

        def run(command, capture_output=False, text=False):  # noqa: ANN001
            self.commands.append(command)
            result = Result()
            result.returncode = returncode
            result.stdout = stdout
            result.stderr = "curl: (22) unauthorized"
            return result

        original = common.subprocess.run
        common.subprocess.run = run
        self.addCleanup(setattr, common.subprocess, "run", original)

    def test_the_title_reaches_gyazo(self) -> None:
        self.fake_run(stdout=json.dumps({"url": STILL_URL}))
        url = common.upload_to_gyazo(self.path, "metaphor reference circle(_:_:_:)")
        self.assertEqual(url, STILL_URL)
        command = self.commands[0]
        self.assertIn("title=metaphor reference circle(_:_:_:)", command)
        self.assertIn("access_token=token-abc", command)
        self.assertIn(f"imagedata=@{self.path}", command)
        self.assertEqual(command[-1], common.GYAZO_UPLOAD_URL)

    def test_a_failed_upload_names_the_subject_without_the_token(self) -> None:
        """どれが失敗したかは分かり、トークンは出ない。"""
        self.fake_run(returncode=22)
        with self.assertRaises(common.ShotError) as caught:
            common.upload_to_gyazo(self.path, "metaphor tutorial 01/02")
        message = str(caught.exception)
        self.assertIn("metaphor tutorial 01/02", message)
        self.assertIn("shot.png", message)
        self.assertNotIn("token-abc", message)


if __name__ == "__main__":
    unittest.main()
