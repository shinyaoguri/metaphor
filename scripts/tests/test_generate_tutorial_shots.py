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
import zlib
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "generate-tutorial-shots.py"
_spec = importlib.util.spec_from_file_location("generate_tutorial_shots", _SCRIPT)
gen = importlib.util.module_from_spec(_spec)
sys.modules["generate_tutorial_shots"] = gen
_spec.loader.exec_module(gen)

REF = "01-Part/02-Section"


def write_png(path: Path, width: int, height: int, seed: int = 0) -> None:
    """`sips` が実際に縮められる本物の PNG を書く（8bit グレースケール）。

    幅の上限（#521）は外部コマンドに縮めさせる処理なので、ヘッダだけの偽物では
    確かめられない。中身はグラデーションで、`seed` を変えると絵が変わる。
    """
    rows = b"".join(
        b"\x00" + bytes((x * 3 + y * 5 + seed) % 256 for x in range(width))
        for y in range(height)
    )

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            len(data).to_bytes(4, "big")
            + tag
            + data
            + (zlib.crc32(tag + data) & 0xFFFFFFFF).to_bytes(4, "big")
        )

    header = (
        width.to_bytes(4, "big") + height.to_bytes(4, "big") + bytes([8, 0, 0, 0, 0])
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(rows, 9))
        + chunk(b"IEND", b"")
    )


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

    def add_section_doc(
        self,
        targets: list[str],
        ref: str = REF,
        name: str = "01-part.md",
        heading: str = "## 1.2 節の見出し",
    ) -> Path:
        """本文らしい形（節見出し → 画像 → 埋め込みマーカー）の 1 節を書く。"""
        lines = ["# 第 1 部", "", heading, ""]
        for index, target in enumerate(targets):
            lines += [f"![説明{index}]({target})", ""]
        lines += ["本文。", "", f"<!-- tutorial-snippet: {ref} -->", "```swift", "```",
                  "<!-- /tutorial-snippet -->", ""]
        path = self.docs / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(lines), encoding="utf-8")
        return path

    def add_image(self, ref: str = REF) -> None:
        path = gen.image_path_for(ref)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"\x89PNG\r\n\x1a\n")

    def record(self, ref: str = REF, motion: dict | None = None) -> dict:
        """台帳のエントリ。画像は外部ストレージにあるので URL を持つ（ADR-0010）。"""
        entry = {
            "sourceHash": gen.source_hash(self.code / ref),
            "url": STILL_URL,
            "sha256": "y",
        }
        if motion is not None:
            entry["motion"] = {**motion, "url": MOTION_URL, "sha256": "z"}
        return {ref: entry}

    def add_body(self, ref: str = REF, motion: bool = False) -> Path:
        """`record()` と対になる本文（台帳が指すのと同じ URL を参照する）。"""
        targets = [STILL_URL] + ([MOTION_URL] if motion else [])
        return self.add_section_doc(targets, ref=ref)

    def write_motion_config(self, sections: dict) -> None:
        self.images.mkdir(parents=True, exist_ok=True)
        (self.images / "motion.json").write_text(
            json.dumps({"sections": sections}), encoding="utf-8"
        )



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
        self.add_body()
        self.assertEqual(gen.check([REF], self.record()), [])

    def test_stale_when_sketch_changed_after_capture(self) -> None:
        package_dir = self.add_package()
        self.add_body()
        recorded = self.record()
        (package_dir / "Section" / "App.swift").write_text(
            "import metaphor\n// 追記\n", encoding="utf-8"
        )
        self.assertEqual(len(gen.check([REF], recorded)), 1)

    def test_stale_when_the_ledger_has_no_url(self) -> None:
        # 画像はもうリポジトリに置かない（ADR-0010）。URL の無いエントリは
        # 「上げていない」ということなので、撮り直しを促す。指紋は合わせておき、
        # URL が無いこと**だけ**が理由で古いと判定されることを確かめる。
        self.add_package()
        self.add_body()
        recorded = {REF: {"sourceHash": gen.source_hash(self.code / REF)}}
        stale = gen.check([REF], recorded)
        self.assertEqual(len(stale), 1)
        self.assertIn("URL", stale[0])

    def test_stale_when_never_captured(self) -> None:
        self.add_package()
        self.add_body()
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
        self.add_body()
        recorded = self.record()
        resource.write_bytes(b"\x89PNG\r\n\x1a\nafter")
        self.assertEqual(len(gen.check([REF], recorded)), 1)

    def test_stale_when_manifest_changed(self) -> None:
        # Package.swift の依存・リソース宣言の変更も絵を変えうる。
        package_dir = self.add_package()
        self.add_body()
        recorded = self.record()
        (package_dir / "Package.swift").write_text(
            "// swift-tools-version: 5.10\n// resources 宣言を追加\n"
        )
        self.assertEqual(len(gen.check([REF], recorded)), 1)

    def test_generated_directories_do_not_change_the_hash(self) -> None:
        # .build / .swiftpm / .metaphor は gitignore 済みの生成物で、
        # あるかないかで撮り直しが要るとは言えない。
        package_dir = self.add_package()
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

    def test_fresh_when_settings_and_assets_match(self) -> None:
        self.add_package()
        self.add_body(motion=True)
        motions = {REF: self.settings()}
        self.assertEqual(gen.check([REF], self.record(motion=self.settings()), motions), [])

    def test_stale_when_motion_was_never_captured(self) -> None:
        self.add_package()
        self.add_body()
        self.assertEqual(len(gen.check([REF], self.record(), {REF: self.settings()})), 1)

    def test_stale_when_settings_changed(self) -> None:
        self.add_package()
        self.add_body(motion=True)
        recorded = self.record(motion=self.settings(fps=15))
        stale = gen.check([REF], recorded, {REF: self.settings(fps=30)})
        self.assertEqual(len(stale), 1)

    def test_stale_when_the_motion_asset_is_missing_from_the_ledger(self) -> None:
        self.add_package()
        self.add_body(motion=True)
        recorded = self.record(motion=self.settings())
        del recorded[REF]["motion"]["url"]
        self.assertEqual(len(gen.check([REF], recorded, {REF: self.settings()})), 1)

    def test_stale_when_section_left_motion_config(self) -> None:
        # 設定から外したのに証跡が台帳に残っている = 撮り直して片付ける。
        self.add_package()
        self.add_body(motion=True)
        recorded = self.record(motion=self.settings())
        self.assertEqual(len(gen.check([REF], recorded, {})), 1)


class TestNoCapture(ShotsTestCase):
    """撮れない節の申告（no-capture.txt）の扱い（#544）。"""

    def declare(self, ref: str = REF, reason: str = "マイク入力は環境で絵が変わる") -> None:
        (self.code / ref / gen.NO_CAPTURE_NAME).write_text(reason + "\n", encoding="utf-8")

    def test_fresh_without_any_image(self) -> None:
        # 撮らないと申告した節は、画像が無くても鮮度検査を通る。
        self.add_package()
        self.declare()
        self.assertEqual(gen.check([REF], {}), [])

    def test_source_change_does_not_make_it_stale(self) -> None:
        package_dir = self.add_package()
        self.declare()
        (package_dir / "Section" / "App.swift").write_text("import metaphor\n// 追記\n")
        self.assertEqual(gen.check([REF], {}), [])

    def test_stale_when_an_old_image_is_left_behind(self) -> None:
        # 撮ってからあとで「撮らない」に変えた節。画像を片付けさせる。
        self.add_package()
        self.add_image()
        self.declare()
        self.assertEqual(len(gen.check([REF], self.record())), 1)

    def test_motion_config_conflicts(self) -> None:
        self.add_package()
        self.declare()
        motions = {REF: {"kind": "webp", **gen.MOTION_DEFAULTS, "quality": None}}
        with self.assertRaises(gen.ShotError):
            gen.check([REF], {}, motions)

    def test_empty_reason_is_an_error(self) -> None:
        self.add_package()
        self.declare(reason="   ")
        with self.assertRaises(gen.ShotError):
            gen.check([REF], {})

    def test_reason_is_returned_for_the_log(self) -> None:
        package_dir = self.add_package()
        self.declare(reason="カメラ映像は撮る場所で変わる\n")
        self.assertEqual(
            gen.no_capture_reason(package_dir, REF), "カメラ映像は撮る場所で変わる"
        )


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


class TestContactSheetWidth(ShotsTestCase):
    """`width` は kind に依らない「幅の上限」（docs/tutorial/README.md の表）。

    以前は縮小が webp の経路にしかなく、`kind: "sheet"` では**どんな値を書いても
    素通り**していた（#521）。シートは格子なので 1 フレームよりずっと広く、台帳の
    `size.width` と比べる webp と同じ判定は使えない、というのがこの節の要点。
    """

    FRAME = (320, 180)
    SHEET = (960, 540)  # 3x3 の格子。1 フレームよりずっと広いのが効いてくる

    def setUp(self) -> None:
        super().setUp()
        original = gen.STAGING_DIR
        gen.STAGING_DIR = self.root / ".build/tutorial-shots"
        self.addCleanup(setattr, gen, "STAGING_DIR", original)

        self.sequence_dir = self.root / "seq"
        frames = []
        for index in range(4):
            name = f"frame-{index}.png"
            write_png(self.sequence_dir / name, *self.FRAME, seed=index * 7)
            frames.append({"file": name})
        write_png(self.sequence_dir / "sheet.png", *self.SHEET)
        self.manifest = {
            "frames": frames,
            "contactSheet": "sheet.png",
            "size": {"width": self.FRAME[0], "height": self.FRAME[1]},
        }

    def collect(self, width: int) -> dict:
        motion = {"kind": "sheet", "frames": 4, "every": 4, "fps": 15,
                  "width": width, "quality": None}
        return gen.collect_sequence(
            REF, self.sequence_dir, self.manifest, motion, self.root / "still.png"
        )

    def sheet_size(self) -> tuple[int, int]:
        return gen.image_size(gen.staging_path_for(REF, "sheet"))

    def test_width_shrinks_the_sheet(self) -> None:
        # 1 フレーム（320）より広くシート（960）より狭い値。ここが #521 の罠で、
        # 台帳の size.width と比べていると「元より大きい」と読んで何もしない。
        entry = self.collect(480)
        self.assertEqual(self.sheet_size(), (480, 270))
        self.assertEqual(entry["motion"]["outputWidth"], 480)
        self.assertEqual(entry["motion"]["outputHeight"], 270)

    def test_width_above_the_sheet_does_not_upscale(self) -> None:
        entry = self.collect(self.SHEET[0] * 2)
        self.assertEqual(self.sheet_size(), self.SHEET)
        self.assertEqual(entry["motion"]["outputWidth"], self.SHEET[0])

    def test_the_still_stays_a_full_size_frame(self) -> None:
        # 縮めるのは動きの証跡だけ。代表静止画は撮ったままの解像度で残す。
        self.collect(160)
        self.assertEqual(gen.image_size(self.root / "still.png"), self.FRAME)


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
    """撮影用の入力台本（`probe-input.jsonl`）のうち、チュートリアル側の扱い（#509）。

    読み取り規則そのものは Examples 側と共有なので test_shots_common.py が見る（#610）。
    """

    def test_script_changes_make_the_shot_stale(self) -> None:
        # 台本はパッケージ配下なので指紋に入る（絵が変わるため撮り直しが要る）
        package_dir = self.add_package()
        self.add_body()
        script = package_dir / gen.INPUT_SCRIPT_NAME
        script.write_text('{"t":"mouseMove","x":5,"y":6}\n', encoding="utf-8")
        shots = self.record()
        self.assertEqual(gen.check([REF], shots), [])
        script.write_text('{"t":"mouseMove","x":9,"y":9}\n', encoding="utf-8")
        self.assertEqual(len(gen.check([REF], shots)), 1)


STILL_URL = "https://i.gyazo.com/1111111111111111111111111111aaaa.png"
MOTION_URL = "https://i.gyazo.com/2222222222222222222222222222bbbb.webp"


class TestDocImageLines(ShotsTestCase):
    """本文の画像を「節の構造」で対応づける（URL の文字列一致では追わない）。"""

    def parse(self, text: str) -> dict:
        return gen.doc_image_lines(text, "01-part.md")

    def test_images_belong_to_the_section_that_embeds_the_sketch(self) -> None:
        self.add_section_doc(["images/01-Part/02-Section.png"])
        text = (self.docs / "01-part.md").read_text(encoding="utf-8")
        self.assertEqual(list(self.parse(text)), [REF])

    def test_still_and_motion_keep_their_order(self) -> None:
        self.add_section_doc(["a.png", "a.webp"])
        text = (self.docs / "01-part.md").read_text(encoding="utf-8")
        lines = text.split("\n")
        indices = self.parse(text)[REF]
        self.assertEqual(len(indices), 2)
        self.assertTrue(lines[indices[0]].endswith("(a.png)"))
        self.assertTrue(lines[indices[1]].endswith("(a.webp)"))

    def test_sections_without_images_are_absent(self) -> None:
        self.add_section_doc([])
        text = (self.docs / "01-part.md").read_text(encoding="utf-8")
        self.assertEqual(self.parse(text), {})

    def test_an_image_outside_a_section_is_an_error(self) -> None:
        with self.assertRaises(gen.ShotError):
            self.parse("![前書きの絵](a.png)\n\n## 1.1 節\n")

    def test_an_image_without_a_marker_is_an_error(self) -> None:
        # どの節の画像か決められない = 台帳と対応づけられない。
        with self.assertRaises(gen.ShotError):
            self.parse("## 1.1 節\n\n![絵](a.png)\n")

    def test_three_images_in_one_section_is_an_error(self) -> None:
        self.add_section_doc(["a.png", "a.webp", "b.png"])
        text = (self.docs / "01-part.md").read_text(encoding="utf-8")
        with self.assertRaises(gen.ShotError):
            self.parse(text)

    def test_inline_images_are_not_touched(self) -> None:
        # 文中に混ぜた画像は規約で認めていない。拾わない（＝書き換えもしない）。
        self.assertEqual(
            self.parse("## 1.1 節\n\n文の途中に ![絵](a.png) がある\n"), {}
        )


class TestRewriteDocs(ShotsTestCase):
    """台帳を正として本文の URL を上書きする（初回も撮り直しも同じ操作）。"""

    def ledger(self, still: str = STILL_URL, motion: str | None = None) -> dict:
        entry = {"sourceHash": "x", "url": still, "sha256": "y"}
        if motion:
            entry["motion"] = {"kind": "webp", "url": motion, "sha256": "z"}
        return {REF: entry}

    def test_relative_paths_become_urls(self) -> None:
        doc = self.add_section_doc(["images/01-Part/02-Section.png"])
        self.assertEqual(gen.rewrite_docs(self.ledger()), [doc])
        self.assertIn(f"![説明0]({STILL_URL})", doc.read_text(encoding="utf-8"))

    def test_alt_text_is_preserved(self) -> None:
        doc = self.add_section_doc(["images/01-Part/02-Section.png"])
        doc.write_text(
            doc.read_text(encoding="utf-8").replace("![説明0]", "![跳ねるボールの実行結果]"),
            encoding="utf-8",
        )
        gen.rewrite_docs(self.ledger())
        self.assertIn(f"![跳ねるボールの実行結果]({STILL_URL})", doc.read_text(encoding="utf-8"))

    def test_an_old_url_is_replaced_by_the_new_one(self) -> None:
        # 撮り直し = 新しいアセット。古い URL は消さないが、本文は新しいほうを指す。
        old = "https://i.gyazo.com/0000000000000000000000000000dead.png"
        doc = self.add_section_doc([old])
        gen.rewrite_docs(self.ledger())
        text = doc.read_text(encoding="utf-8")
        self.assertIn(STILL_URL, text)
        self.assertNotIn(old, text)

    def test_rewriting_twice_changes_nothing(self) -> None:
        doc = self.add_section_doc(["images/01-Part/02-Section.png"])
        gen.rewrite_docs(self.ledger())
        before = doc.read_text(encoding="utf-8")
        self.assertEqual(gen.rewrite_docs(self.ledger()), [])
        self.assertEqual(doc.read_text(encoding="utf-8"), before)

    def test_a_broken_body_is_repaired_from_the_ledger(self) -> None:
        # 途中で中断して本文だけ古い / 手で壊した状態からでも、位置で決めて直せる。
        doc = self.add_section_doc(["まったく別の文字列.png", "images/x.webp"])
        gen.rewrite_docs(self.ledger(motion=MOTION_URL))
        text = doc.read_text(encoding="utf-8")
        self.assertIn(f"![説明0]({STILL_URL})", text)
        self.assertIn(f"![説明1]({MOTION_URL})", text)

    def test_sections_without_a_url_are_left_alone(self) -> None:
        # 移行の途中。まだ上げていない節は相対パスのまま壊さない。
        doc = self.add_section_doc(["images/01-Part/02-Section.png"])
        self.assertEqual(gen.rewrite_docs({REF: {"sourceHash": "x"}}), [])
        self.assertIn("images/01-Part/02-Section.png", doc.read_text(encoding="utf-8"))

    def test_image_count_mismatch_is_an_error(self) -> None:
        # 本文は 1 本なのに台帳は 2 本（motion.json を足して本文を直し忘れた）。
        self.add_section_doc(["images/01-Part/02-Section.png"])
        with self.assertRaises(gen.ShotError):
            gen.rewrite_docs(self.ledger(motion=MOTION_URL))

    def test_translations_share_the_same_assets(self) -> None:
        # 英語版（#548）は本文が別ファイルでも同じ台帳から書き換える。
        doc = self.add_section_doc(["images/01-Part/02-Section.png"])
        translated = self.add_section_doc(
            ["images/01-Part/02-Section.png"], name="en/01-part.md"
        )
        self.assertEqual(set(gen.rewrite_docs(self.ledger())), {doc, translated})
        self.assertIn(STILL_URL, translated.read_text(encoding="utf-8"))


class TestExternalStaleness(ShotsTestCase):
    """外部ストレージへ移した節の鮮度（ADR-0010）。ローカルの画像は見ない。"""

    def external(self, motion_url: str | None = None) -> dict:
        entry = {
            "sourceHash": gen.source_hash(self.code / REF),
            "url": STILL_URL,
            "sha256": "y",
        }
        if motion_url:
            entry["motion"] = {
                "kind": "webp",
                **gen.MOTION_DEFAULTS,
                "quality": None,
                "url": motion_url,
                "sha256": "z",
            }
        return {REF: entry}

    def test_fresh_without_any_local_file(self) -> None:
        self.add_package()
        self.add_section_doc([STILL_URL])
        self.assertEqual(gen.check([REF], self.external()), [])

    def test_stale_when_the_body_points_elsewhere(self) -> None:
        self.add_package()
        self.add_section_doc(["https://i.gyazo.com/0000000000000000000000000000dead.png"])
        self.assertEqual(len(gen.check([REF], self.external())), 1)

    def test_stale_when_the_body_still_uses_a_relative_path(self) -> None:
        self.add_package()
        self.add_section_doc(["images/01-Part/02-Section.png"])
        self.assertEqual(len(gen.check([REF], self.external())), 1)

    def test_stale_when_the_sketch_changed(self) -> None:
        package_dir = self.add_package()
        self.add_section_doc([STILL_URL])
        recorded = self.external()
        (package_dir / "Section" / "App.swift").write_text("import metaphor\n// 追記\n")
        self.assertEqual(len(gen.check([REF], recorded)), 1)

    def test_stale_when_the_motion_asset_is_not_in_the_ledger(self) -> None:
        self.add_package()
        self.add_section_doc([STILL_URL])
        motions = {REF: {"kind": "webp", **gen.MOTION_DEFAULTS, "quality": None}}
        recorded = self.external()
        recorded[REF]["motion"] = {"kind": "webp", **gen.MOTION_DEFAULTS, "quality": None}
        self.assertEqual(len(gen.check([REF], recorded, motions)), 1)

    def test_fresh_with_both_assets(self) -> None:
        self.add_package()
        self.add_section_doc([STILL_URL, MOTION_URL])
        motions = {REF: {"kind": "webp", **gen.MOTION_DEFAULTS, "quality": None}}
        self.assertEqual(gen.check([REF], self.external(MOTION_URL), motions), [])

    def test_stale_when_the_body_dropped_the_images(self) -> None:
        self.add_package()
        self.add_section_doc([])
        self.assertEqual(len(gen.check([REF], self.external())), 1)

    def test_a_translation_that_drifted_is_reported(self) -> None:
        self.add_package()
        self.add_section_doc([STILL_URL])
        self.add_section_doc(["images/01-Part/02-Section.png"], name="en/01-part.md")
        stale = gen.check([REF], self.external())
        self.assertEqual(len(stale), 1)
        self.assertIn("01-part.md", stale[0])

    def test_local_files_do_not_matter_once_external(self) -> None:
        # 移行後にローカルへ残骸が復活しても、参照されていないので鮮度には効かない。
        self.add_package()
        self.add_section_doc([STILL_URL])
        self.add_image()
        self.assertEqual(gen.check([REF], self.external()), [])


class TestUploadSkipsUnchangedAssets(ShotsTestCase):
    """同じバイト列を上げ直さない（アップロードだけ失敗した再実行を速くする）。"""

    def test_same_digest_reuses_the_recorded_url(self) -> None:
        path = self.root / "shot.png"
        path.write_bytes(b"\x89PNG\r\n\x1a\ncontent")
        recorded = {"url": STILL_URL, "sha256": gen.file_sha256(path)}
        # upload_to_gyazo を呼ばない（トークンが無い環境でも通る）ことが要点。
        self.assertEqual(
            gen.upload_asset(REF, path, recorded), (STILL_URL, recorded["sha256"])
        )

    def test_changed_bytes_are_uploaded_again(self) -> None:
        path = self.root / "shot.png"
        path.write_bytes(b"\x89PNG\r\n\x1a\nnew")
        recorded = {"url": STILL_URL, "sha256": "他のバイト列の指紋"}
        calls: list[Path] = []
        original = gen.upload_to_gyazo
        gen.upload_to_gyazo = lambda p, ref: calls.append(p) or MOTION_URL
        self.addCleanup(setattr, gen, "upload_to_gyazo", original)
        url, digest = gen.upload_asset(REF, path, recorded)
        self.assertEqual((url, calls), (MOTION_URL, [path]))
        self.assertEqual(digest, gen.file_sha256(path))


if __name__ == "__main__":
    unittest.main()
