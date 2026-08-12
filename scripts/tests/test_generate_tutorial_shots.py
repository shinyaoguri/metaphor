#!/usr/bin/env python3
"""Unit tests for scripts/generate-tutorial-shots.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

撮影そのものは GPU とウィンドウサーバーが要るので、ここで確かめるのは
**鮮度判定の規則**だけ。PNG のバイト比較ではなく「撮影時のソースの指紋と
現在のソースが一致するか」で判定する、というのがこのスクリプトの肝で、
そこが壊れると「コードを変えたのに画像が古い」を CI が見逃す（#486）。
"""

import importlib.util
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "generate-tutorial-shots.py"
_spec = importlib.util.spec_from_file_location("generate_tutorial_shots", _SCRIPT)
gen = importlib.util.module_from_spec(_spec)
sys.modules["generate_tutorial_shots"] = gen
_spec.loader.exec_module(gen)

REF = "01-Part/02-Section"


class ShotsTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.docs = self.root / "docs/tutorial"
        self.images = self.docs / "images"
        self.code = self.root / "Examples/Tutorial"
        self.docs.mkdir(parents=True)
        self.code.mkdir(parents=True)
        for name, value in (
            ("REPO_ROOT", self.root),
            ("DOCS_DIR", self.docs),
            ("IMAGES_DIR", self.images),
            ("CODE_DIR", self.code),
            ("MANIFEST", self.images / "manifest.json"),
            ("MOTION_CONFIG", self.images / "motion.json"),
        ):
            original = getattr(gen, name)
            setattr(gen, name, value)
            self.addCleanup(setattr, gen, name, original)

    def add_package(self, ref: str = REF, body: str = "import metaphor\n") -> Path:
        package_dir = self.code / ref
        (package_dir / "Section").mkdir(parents=True)
        (package_dir / "Package.swift").write_text("// swift-tools-version: 5.10\n")
        (package_dir / "Section" / "App.swift").write_text(body, encoding="utf-8")
        return package_dir

    def add_doc(self, ref: str = REF) -> None:
        (self.docs / "01-part.md").write_text(
            f"<!-- tutorial-snippet: {ref} -->\n<!-- /tutorial-snippet -->\n",
            encoding="utf-8",
        )

    def add_image(self, ref: str = REF) -> None:
        path = gen.image_path_for(ref)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"\x89PNG\r\n\x1a\n")

    def record(self, ref: str = REF, motion: dict | None = None) -> dict:
        entry = {"sourceHash": gen.source_hash(self.code / ref)}
        if motion is not None:
            entry["motion"] = motion
        return {ref: entry}

    def write_motion_config(self, sections: dict) -> None:
        self.images.mkdir(parents=True, exist_ok=True)
        (self.images / "motion.json").write_text(
            json.dumps({"sections": sections}), encoding="utf-8"
        )

    def add_motion_file(self, ref: str = REF, kind: str = "webp") -> None:
        path = gen.motion_path_for(ref, kind)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"RIFF____WEBP")


class TestReferencedRefs(ShotsTestCase):
    def test_reads_snippet_markers(self) -> None:
        self.add_doc()
        self.assertEqual(gen.referenced_refs(), [REF])

    def test_readme_is_not_scanned(self) -> None:
        (self.docs / "README.md").write_text(
            f"<!-- tutorial-snippet: {REF} -->\n<!-- /tutorial-snippet -->\n",
            encoding="utf-8",
        )
        self.assertEqual(gen.referenced_refs(), [])


class TestStaleness(ShotsTestCase):
    def test_fresh_when_hash_matches(self) -> None:
        self.add_package()
        self.add_image()
        self.assertEqual(gen.check([REF], self.record()), [])

    def test_stale_when_sketch_changed_after_capture(self) -> None:
        package_dir = self.add_package()
        self.add_image()
        recorded = self.record()
        (package_dir / "Section" / "App.swift").write_text(
            "import metaphor\n// 追記\n", encoding="utf-8"
        )
        self.assertEqual(len(gen.check([REF], recorded)), 1)

    def test_stale_when_image_missing(self) -> None:
        self.add_package()
        self.assertEqual(len(gen.check([REF], self.record())), 1)

    def test_stale_when_never_captured(self) -> None:
        self.add_package()
        self.add_image()
        self.assertEqual(len(gen.check([REF], {})), 1)

    def test_unknown_package_is_an_error(self) -> None:
        with self.assertRaises(gen.ShotError):
            gen.check(["99-Missing/99-Missing"], {})

    def test_stale_when_resource_changed(self) -> None:
        # 画像・シェーダー・データファイルを差し替えても絵は変わる（#505）。
        package_dir = self.add_package()
        resource = package_dir / "Section/Resources/sample.png"
        resource.parent.mkdir(parents=True)
        resource.write_bytes(b"\x89PNG\r\n\x1a\nbefore")
        self.add_image()
        recorded = self.record()
        resource.write_bytes(b"\x89PNG\r\n\x1a\nafter")
        self.assertEqual(len(gen.check([REF], recorded)), 1)

    def test_stale_when_manifest_changed(self) -> None:
        # Package.swift の依存・リソース宣言の変更も絵を変えうる。
        package_dir = self.add_package()
        self.add_image()
        recorded = self.record()
        (package_dir / "Package.swift").write_text(
            "// swift-tools-version: 5.10\n// resources 宣言を追加\n"
        )
        self.assertEqual(len(gen.check([REF], recorded)), 1)

    def test_generated_directories_do_not_change_the_hash(self) -> None:
        # .build / .swiftpm / .metaphor は gitignore 済みの生成物で、
        # あるかないかで撮り直しが要るとは言えない。
        package_dir = self.add_package()
        self.add_image()
        before = gen.source_hash(package_dir)
        for relative, name, body in (
            (".build/checkouts/dep", "Dep.swift", "import Foundation\n"),
            (".swiftpm/xcode", "settings.json", "{}\n"),
            (".metaphor/probe/current", "frame.json", "{}\n"),
        ):
            directory = package_dir / relative
            directory.mkdir(parents=True)
            (directory / name).write_text(body)
        (package_dir / ".DS_Store").write_bytes(b"\x00\x00\x00\x01Bud1")
        self.assertEqual(gen.source_hash(package_dir), before)


class TestMotionConfig(ShotsTestCase):
    """動きが要る節の設定（docs/tutorial/images/motion.json）の読み取り（#507）。"""

    def test_missing_file_is_empty(self) -> None:
        self.assertEqual(gen.load_motion_config(), {})

    def test_defaults_fill_in(self) -> None:
        self.write_motion_config({REF: {"kind": "webp"}})
        config = gen.load_motion_config()[REF]
        self.assertEqual(config["kind"], "webp")
        self.assertEqual(config["frames"], gen.MOTION_DEFAULTS["frames"])
        self.assertEqual(config["every"], gen.MOTION_DEFAULTS["every"])
        self.assertIsNone(config["quality"])

    def test_unknown_kind_is_an_error(self) -> None:
        self.write_motion_config({REF: {"kind": "gif"}})
        with self.assertRaises(gen.ShotError):
            gen.load_motion_config()

    def test_frames_above_the_probe_limit_is_an_error(self) -> None:
        # Probe 側が 64 でクランプする（CONTRACT.md 契約点 4）。黙って丸めない。
        self.write_motion_config({REF: {"kind": "webp", "frames": 128}})
        with self.assertRaises(gen.ShotError):
            gen.load_motion_config()

    def test_single_frame_is_an_error(self) -> None:
        self.write_motion_config({REF: {"kind": "webp", "frames": 1}})
        with self.assertRaises(gen.ShotError):
            gen.load_motion_config()

    def test_non_integer_setting_is_an_error(self) -> None:
        self.write_motion_config({REF: {"kind": "webp", "fps": "15"}})
        with self.assertRaises(gen.ShotError):
            gen.load_motion_config()


class TestMotionStaleness(ShotsTestCase):
    def settings(self, **overrides) -> dict:
        base = {"kind": "webp", **gen.MOTION_DEFAULTS, "quality": None}
        base.update(overrides)
        return base

    def test_fresh_when_settings_and_file_match(self) -> None:
        self.add_package()
        self.add_image()
        self.add_motion_file()
        motions = {REF: self.settings()}
        recorded = self.record(motion={**self.settings(), "file": "02-Section.webp"})
        self.assertEqual(gen.check([REF], recorded, motions), [])

    def test_stale_when_motion_was_never_captured(self) -> None:
        self.add_package()
        self.add_image()
        self.assertEqual(len(gen.check([REF], self.record(), {REF: self.settings()})), 1)

    def test_stale_when_settings_changed(self) -> None:
        self.add_package()
        self.add_image()
        self.add_motion_file()
        recorded = self.record(motion=self.settings(fps=15))
        stale = gen.check([REF], recorded, {REF: self.settings(fps=30)})
        self.assertEqual(len(stale), 1)

    def test_stale_when_motion_file_is_missing(self) -> None:
        self.add_package()
        self.add_image()
        recorded = self.record(motion=self.settings())
        self.assertEqual(len(gen.check([REF], recorded, {REF: self.settings()})), 1)

    def test_stale_when_section_left_motion_config(self) -> None:
        # 設定から外したのに証跡が manifest に残っている = 撮り直して片付ける。
        self.add_package()
        self.add_image()
        self.add_motion_file()
        recorded = self.record(motion=self.settings())
        self.assertEqual(len(gen.check([REF], recorded, {})), 1)


class TestWebPCommand(ShotsTestCase):
    def test_frame_delay_comes_from_fps(self) -> None:
        command = gen.webp_command([Path("a.png"), Path("b.png")], Path("out.webp"), 15, None)
        self.assertIn("-d", command)
        self.assertEqual(command[command.index("-d") + 1], "67")
        # 品質指定が無ければ img2webp に lossy / lossless を選ばせる。
        self.assertIn("-mixed", command)
        self.assertNotIn("-lossy", command)

    def test_quality_switches_to_lossy(self) -> None:
        command = gen.webp_command([Path("a.png")], Path("out.webp"), 30, 70)
        self.assertIn("-lossy", command)
        self.assertEqual(command[command.index("-q") + 1], "70")
        self.assertNotIn("-mixed", command)

    def test_frames_keep_their_order_and_output_is_last(self) -> None:
        frames = [Path(f"frame.{i:04d}.png") for i in range(3)]
        command = gen.webp_command(frames, Path("out.webp"), 15, None)
        positions = [command.index(str(path)) for path in frames]
        self.assertEqual(positions, sorted(positions))
        self.assertEqual(command[-2:], ["-o", "out.webp"])

    def test_loops_forever(self) -> None:
        command = gen.webp_command([Path("a.png")], Path("out.webp"), 15, None)
        self.assertEqual(command[command.index("-loop") + 1], "0")


class TestMotionPaths(ShotsTestCase):
    def test_webp_sits_next_to_the_still(self) -> None:
        self.assertEqual(
            gen.motion_path_for(REF, "webp").name, "02-Section.webp"
        )

    def test_contact_sheet_is_suffixed(self) -> None:
        self.assertEqual(
            gen.motion_path_for(REF, "sheet").name, "02-Section.sheet.png"
        )


class TestSequenceReadiness(ShotsTestCase):
    """CONTRACT.md 契約点 4 の完了規約（sequence.json が最後・id エコー）。"""

    def write_manifest(self, sequence_dir: Path, payload: dict) -> None:
        sequence_dir.mkdir(parents=True, exist_ok=True)
        (sequence_dir / "sequence.json").write_text(json.dumps(payload), encoding="utf-8")

    def test_none_until_the_manifest_appears(self) -> None:
        self.assertIsNone(gen.sequence_manifest(self.root / "seq", "req-1"))

    def test_ready_when_id_and_count_match(self) -> None:
        seq = self.root / "seq"
        self.write_manifest(seq, {"id": "req-1", "frameCount": 2, "frames": [{}, {}]})
        self.assertIsNotNone(gen.sequence_manifest(seq, "req-1"))

    def test_not_ready_for_a_previous_request(self) -> None:
        seq = self.root / "seq"
        self.write_manifest(seq, {"id": "older", "frameCount": 2, "frames": [{}, {}]})
        self.assertIsNone(gen.sequence_manifest(seq, "req-1"))

    def test_not_ready_when_frames_are_short(self) -> None:
        seq = self.root / "seq"
        self.write_manifest(seq, {"id": "req-1", "frameCount": 4, "frames": [{}, {}]})
        self.assertIsNone(gen.sequence_manifest(seq, "req-1"))

    def test_partial_write_is_not_ready(self) -> None:
        seq = self.root / "seq"
        seq.mkdir(parents=True)
        (seq / "sequence.json").write_text('{"id": "req-1", "frame', encoding="utf-8")
        self.assertIsNone(gen.sequence_manifest(seq, "req-1"))


class TestCurrentFrame(ShotsTestCase):
    """単一フレームの応答も **id 一致**で見る（下見の応答と取り違えないため。#509）。"""

    def write_frame(self, output_dir: Path, payload: dict, png: bool = True) -> None:
        output_dir.mkdir(parents=True, exist_ok=True)
        (output_dir / "frame.json").write_text(json.dumps(payload), encoding="utf-8")
        if png:
            (output_dir / "frame.png").write_bytes(b"\x89PNG\r\n\x1a\n")

    def test_none_until_the_frame_appears(self) -> None:
        self.assertIsNone(gen.current_frame(self.root / "current", "req-1"))

    def test_ready_when_id_matches(self) -> None:
        current = self.root / "current"
        self.write_frame(current, {"id": "req-1", "frame": 12})
        self.assertEqual(gen.current_frame(current, "req-1"), {"id": "req-1", "frame": 12})

    def test_not_ready_for_the_warmup_response(self) -> None:
        current = self.root / "current"
        self.write_frame(current, {"id": "req-1-warmup", "frame": 3})
        self.assertIsNone(gen.current_frame(current, "req-1"))

    def test_failure_response_is_returned_without_a_png(self) -> None:
        # 失敗応答は frame.json だけが書かれる（契約点 4）。ready として返し、
        # 呼び出し側が PNG の不在を見て warnings をエラーにする
        current = self.root / "current"
        self.write_frame(current, {"id": "req-1", "warnings": ["no staging texture"]}, png=False)
        answer = gen.current_frame(current, "req-1")
        self.assertEqual(answer.get("warnings"), ["no staging texture"])

    def test_partial_write_is_not_ready(self) -> None:
        current = self.root / "current"
        current.mkdir(parents=True)
        (current / "frame.json").write_text('{"id": "req-', encoding="utf-8")
        self.assertIsNone(gen.current_frame(current, "req-1"))


class TestInputScript(ShotsTestCase):
    """撮影用の入力台本（`probe-input.jsonl`）の読み取り規則（#509）。"""

    def parse(self, text: str) -> list[dict]:
        return gen.parse_input_script(text, REF)

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
        with self.assertRaises(gen.ShotError):
            self.parse('{"x":10,"y":20}\n')

    def test_a_negative_wait_is_an_error(self) -> None:
        with self.assertRaises(gen.ShotError):
            self.parse('{"wait":-5}\n')

    def test_broken_json_is_an_error(self) -> None:
        with self.assertRaises(gen.ShotError):
            self.parse('{"t":"mouseMove",\n')

    def test_a_script_without_events_is_an_error(self) -> None:
        with self.assertRaises(gen.ShotError):
            self.parse("// 説明だけ\n\n")

    def test_missing_script_means_no_input(self) -> None:
        package_dir = self.add_package()
        self.assertIsNone(gen.load_input_script(package_dir, REF))

    def test_script_is_read_from_the_package_root(self) -> None:
        package_dir = self.add_package()
        (package_dir / gen.INPUT_SCRIPT_NAME).write_text(
            '{"t":"mouseMove","x":5,"y":6}\n', encoding="utf-8"
        )
        self.assertEqual(len(gen.load_input_script(package_dir, REF) or []), 1)

    def test_script_changes_make_the_shot_stale(self) -> None:
        # 台本はパッケージ配下なので指紋に入る（絵が変わるため撮り直しが要る）
        package_dir = self.add_package()
        self.add_doc()
        self.add_image()
        script = package_dir / gen.INPUT_SCRIPT_NAME
        script.write_text('{"t":"mouseMove","x":5,"y":6}\n', encoding="utf-8")
        shots = self.record()
        self.assertEqual(gen.check([REF], shots), [])
        script.write_text('{"t":"mouseMove","x":9,"y":9}\n', encoding="utf-8")
        self.assertEqual(len(gen.check([REF], shots)), 1)


if __name__ == "__main__":
    unittest.main()
