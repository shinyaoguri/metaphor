#!/usr/bin/env python3
"""Unit tests for scripts/generate-example-shots.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

撮影そのものは GPU が要るので、ここで確かめるのは**撮る前後の判断**だけ。

- `noLoop()` の有無で撮り方が変わる（動く example は下見を挟まないと 1 フレーム目
  = 真っ黒や初期姿勢を撮ってしまう。#501 の実測）
- 原典由来（`origin: processing`）は鮮度判定の対象外で、撮ったもの
  （`origin: captured`）だけがソース変更で stale になる
- 撮らない申告（`no-capture.txt`）を尊重し、入力台本（`probe-input.jsonl`）がある
  example は**撮る対象になる**（#610）
"""

import importlib.util
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "generate-example-shots.py"
_spec = importlib.util.spec_from_file_location("generate_example_shots", _SCRIPT)
gen = importlib.util.module_from_spec(_spec)
sys.modules["generate_example_shots"] = gen
_spec.loader.exec_module(gen)

PATH = "Examples/Topics/Geometry/Toroid"


class ExampleShotsTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        for name, value in (
            ("REPO_ROOT", self.root),
            ("EXAMPLES_DIR", self.root / "Examples"),
            ("INDEX", self.root / "docs/ai/examples-index.json"),
            ("MANIFEST", self.root / "docs/ai/examples-shots.json"),
            ("CONFIG", self.root / "docs/ai/examples-shots.config.json"),
        ):
            original = getattr(gen, name)
            setattr(gen, name, value)
            self.addCleanup(setattr, gen, name, original)
        gen.INDEX.parent.mkdir(parents=True)

    def package(self, path: str = PATH, source: str = "func draw() {}\n") -> Path:
        package = self.root / path
        (package / "Sketch").mkdir(parents=True)
        (package / "Package.swift").write_text("// swift-tools-version: 5.10\n")
        (package / "Sketch/App.swift").write_text(source)
        return package

    def write_index(self, *entries: dict) -> None:
        gen.INDEX.write_text(json.dumps({"examples": list(entries)}), encoding="utf-8")

    def entry(self, path: str = PATH, status: str = "supported") -> dict:
        return {"path": path, "title": Path(path).name, "status": status}

    def image(self, path: str = PATH) -> Path:
        image = gen.image_path_for(path)
        image.parent.mkdir(parents=True, exist_ok=True)
        # 縦横をヘッダから読むので、IHDR まで作れば足りる。
        image.write_bytes(
            b"\x89PNG\r\n\x1a\n"
            + (13).to_bytes(4, "big")
            + b"IHDR"
            + (640).to_bytes(4, "big")
            + (360).to_bytes(4, "big")
        )
        return image


class TestTargets(ExampleShotsTestCase):
    """索引のどれを撮る対象と見るか。"""

    def test_only_supported_examples_are_targets(self) -> None:
        self.write_index(
            self.entry("Examples/A/One"),
            self.entry("Examples/A/Two", status="stub"),
            self.entry("Examples/A/Three", status="obsolete"),
        )
        self.assertEqual([e["path"] for e in gen.load_index()], ["Examples/A/One"])

    def test_tutorial_packages_belong_to_the_other_script(self) -> None:
        self.write_index(
            self.entry("Examples/Basics/Form/Bezier"),
            self.entry("Examples/Tutorial/01-GettingStarted/02-FirstSketch"),
        )
        self.assertEqual(
            [e["path"] for e in gen.load_index()], ["Examples/Basics/Form/Bezier"]
        )

    def test_only_narrows_by_prefix(self) -> None:
        entries = [self.entry("Examples/Basics/Form/Bezier"), self.entry("Examples/Topics/GUI/Button")]
        self.assertEqual(
            [e["path"] for e in gen.selected(entries, "Examples/Basics")],
            ["Examples/Basics/Form/Bezier"],
        )

    def test_only_that_matches_nothing_is_an_error(self) -> None:
        with self.assertRaises(gen.ShotError):
            gen.selected([self.entry()], "Examples/Nope")


class TestNoLoop(ExampleShotsTestCase):
    """`noLoop()` の有無で撮り方（下見を挟むか）が変わる。"""

    def test_a_sketch_that_stops_is_still(self) -> None:
        package = self.package(source="func setup() { noLoop() }\n")
        self.assertTrue(gen.uses_no_loop(package))

    def test_a_sketch_that_keeps_drawing_is_not(self) -> None:
        package = self.package(source="func draw() { circle(0, 0, 10) }\n")
        self.assertFalse(gen.uses_no_loop(package))

    def test_a_mention_in_a_comment_does_not_count(self) -> None:
        # コメントで noLoop() に触れているだけの節を「止まる」と誤判定すると、
        # 下見を挟まずに 1 フレーム目（真っ黒や初期姿勢）を撮ってしまう。
        package = self.package(source="// noLoop() は使わない\nfunc draw() {}\n")
        self.assertFalse(gen.uses_no_loop(package))

    def test_build_artifacts_are_ignored(self) -> None:
        package = self.package(source="func draw() {}\n")
        artifact = package / ".build/debug/Generated.swift"
        artifact.parent.mkdir(parents=True)
        artifact.write_text("noLoop()\n")
        self.assertFalse(gen.uses_no_loop(package))


class TestNoCapture(ExampleShotsTestCase):
    """撮らない申告。"""

    def test_no_capture_reports_the_written_reason(self) -> None:
        package = self.package()
        (package / gen.NO_CAPTURE_NAME).write_text("カメラの映像は撮る場所で変わる\n")
        self.assertEqual(gen.no_capture_reason(package), "カメラの映像は撮る場所で変わる")

    def test_an_empty_no_capture_still_skips(self) -> None:
        package = self.package()
        (package / gen.NO_CAPTURE_NAME).write_text("\n")
        self.assertIn(gen.NO_CAPTURE_NAME, gen.no_capture_reason(package) or "")

    def test_a_plain_package_is_captured(self) -> None:
        self.assertIsNone(gen.no_capture_reason(self.package()))


class TestInputScript(ExampleShotsTestCase):
    """入力台本（`probe-input.jsonl`）の扱い（#509 / #610）。"""

    def with_script(self, source: str = "func draw() {}\n") -> Path:
        package = self.package(source=source)
        (package / gen.INPUT_SCRIPT_NAME).write_text('{"t":"mouseMove","x":1,"y":2}\n')
        return package

    def test_an_input_script_is_captured_not_skipped(self) -> None:
        # 台本は「撮らない申告」ではなく「こう撮る」という指定（#610 以前は除外していた）
        self.assertIsNone(gen.no_capture_reason(self.with_script()))

    def test_the_script_is_read_from_the_package_root(self) -> None:
        package = self.with_script()
        events = gen.input_script_for(package, PATH, still=False)
        self.assertEqual(events, [{"t": "mouseMove", "x": 1, "y": 2}])

    def test_no_script_means_no_input(self) -> None:
        self.assertIsNone(gen.input_script_for(self.package(), PATH, still=False))

    def test_a_script_on_a_stopped_sketch_is_an_error(self) -> None:
        # noLoop() のスケッチは起動後に置く request を処理しない。黙って入力なしで
        # 撮ると「台本を書いたのに効いていない絵」が台帳へ入る。
        package = self.with_script(source="func setup() { noLoop() }\n")
        with self.assertRaises(gen.ShotError):
            gen.input_script_for(package, PATH, still=gen.uses_no_loop(package))

    def test_a_broken_script_is_an_error(self) -> None:
        package = self.package()
        (package / gen.INPUT_SCRIPT_NAME).write_text('{"x":1,"y":2}\n')
        with self.assertRaises(gen.ShotError):
            gen.input_script_for(package, PATH, still=False)

    def test_script_changes_make_the_shot_stale(self) -> None:
        # 台本はパッケージ配下なので指紋に入る（絵が変わるため撮り直しが要る）
        package = self.with_script()
        self.image()
        shots = {
            PATH: {
                "origin": gen.ORIGIN_CAPTURED,
                "sourceHash": gen.source_fingerprint(PATH),
                "width": 640,
                "height": 360,
            }
        }
        self.assertEqual(gen.stale_entries([self.entry()], shots), [])
        (package / gen.INPUT_SCRIPT_NAME).write_text('{"t":"mouseMove","x":9,"y":9}\n')
        self.assertEqual(len(gen.stale_entries([self.entry()], shots)), 1)


class TestManifest(ExampleShotsTestCase):
    """台帳を実態に合わせる（原典由来を迎え入れ、消えた画像を落とす）。"""

    def test_an_existing_image_is_adopted_as_processing(self) -> None:
        self.package()
        self.image()
        adopted = gen.adopted([self.entry()], {})
        self.assertEqual(
            adopted[PATH],
            {"origin": gen.ORIGIN_PROCESSING, "width": 640, "height": 360},
        )

    def test_a_removed_image_drops_out(self) -> None:
        self.package()
        recorded = {PATH: {"origin": gen.ORIGIN_PROCESSING, "width": 640, "height": 360}}
        self.assertEqual(gen.adopted([self.entry()], recorded), {})

    def test_an_entry_that_left_the_index_drops_out(self) -> None:
        recorded = {"Examples/Gone/Sketch": {"origin": gen.ORIGIN_CAPTURED}}
        self.assertEqual(gen.adopted([], recorded), {})

    def test_a_captured_entry_is_left_alone(self) -> None:
        self.package()
        self.image()
        recorded = {
            PATH: {
                "origin": gen.ORIGIN_CAPTURED,
                "sourceHash": gen.source_fingerprint(PATH),
                "width": 640,
                "height": 360,
            }
        }
        self.assertEqual(gen.adopted([self.entry()], recorded), recorded)


class TestStaleness(ExampleShotsTestCase):
    """鮮度判定。原典由来は対象外で、撮ったものだけがソース変更で古くなる。"""

    def captured(self) -> dict:
        return {
            PATH: {
                "origin": gen.ORIGIN_CAPTURED,
                "sourceHash": gen.source_fingerprint(PATH),
                "width": 640,
                "height": 360,
            }
        }

    def test_an_unchanged_capture_is_fresh(self) -> None:
        self.package()
        self.image()
        self.assertEqual(gen.stale_entries([self.entry()], self.captured()), [])

    def test_changing_the_sketch_makes_it_stale(self) -> None:
        package = self.package()
        self.image()
        shots = self.captured()
        (package / "Sketch/App.swift").write_text("func draw() { circle(0, 0, 10) }\n")
        self.assertEqual(len(gen.stale_entries([self.entry()], shots)), 1)

    def test_replacing_the_image_alone_is_not_stale(self) -> None:
        # 指紋は入力の指紋。実行結果画像は出力なので、差し替えても
        # 「ソースが変わった」にはならない（#820）。
        self.package()
        image = self.image()
        shots = self.captured()
        image.write_bytes(image.read_bytes() + b"\x00")
        self.assertEqual(gen.stale_entries([self.entry()], shots), [])

    def test_a_missing_image_makes_it_stale(self) -> None:
        self.package()
        shots = self.captured()
        self.assertEqual(len(gen.stale_entries([self.entry()], shots)), 1)

    def test_a_processing_image_never_goes_stale(self) -> None:
        # 撮影時のソースが分からないので、指紋で古さを言えない（#501）。
        package = self.package()
        self.image()
        shots = {PATH: {"origin": gen.ORIGIN_PROCESSING, "width": 640, "height": 360}}
        (package / "Sketch/App.swift").write_text("func draw() { circle(0, 0, 10) }\n")
        self.assertEqual(gen.stale_entries([self.entry()], shots), [])

    def test_a_skipped_example_does_not_go_stale(self) -> None:
        package = self.package()
        self.image()
        shots = self.captured()
        (package / gen.NO_CAPTURE_NAME).write_text("実行環境に依存する\n")
        (package / "Sketch/App.swift").write_text("func draw() { circle(0, 0, 10) }\n")
        self.assertEqual(gen.stale_entries([self.entry()], shots), [])


class TestSettle(ExampleShotsTestCase):
    """待ち時間の例外（手書き設定）。"""

    def write_config(self, payload: dict) -> None:
        gen.CONFIG.write_text(json.dumps(payload), encoding="utf-8")

    def test_the_default_is_used_without_a_config(self) -> None:
        self.assertEqual(gen.settle_for(PATH, gen.load_config()), gen.SETTLE_SEC)

    def test_a_config_entry_overrides_the_default(self) -> None:
        self.write_config({"settings": {PATH: {"settle": 4}}})
        self.assertEqual(gen.settle_for(PATH, gen.load_config()), 4.0)

    def test_a_negative_settle_is_an_error(self) -> None:
        self.write_config({"settings": {PATH: {"settle": -1}}})
        with self.assertRaises(gen.ShotError):
            gen.settle_for(PATH, gen.load_config())

    def test_a_non_numeric_settle_is_an_error(self) -> None:
        self.write_config({"settings": {PATH: {"settle": "しばらく"}}})
        with self.assertRaises(gen.ShotError):
            gen.settle_for(PATH, gen.load_config())


if __name__ == "__main__":
    unittest.main()
