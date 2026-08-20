#!/usr/bin/env python3
"""Unit tests for scripts/generate-reference-shots.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

確かめるのは、GPU とネットワークと Gyazo トークンが要らない 6 つ。

- **抽出** — doc コメントから撮影対象を拾い、宣言から DocC と同じシンボル表記を作る。
  ここが狂うと、別のシンボルのページに絵が出る
- **ターゲット名** — オーバーロード（`rect()` の 3 種）が別ターゲットになる。同名になると
  生成パッケージが `duplicate target named ...` で落ち、そのファイルの撮影が丸ごと止まる
- **書き戻し** — 生成物領域の組み立てがべき等（2 回走らせても差分が出ない）。横並び
  （`@Row`）と縦積みの行き来と、字下げが積み増されないこと
- **台帳の掃除** — `--only` で絞っているときは掃除しない。絞ったまま掃除すると、
  視界の外のエントリを「消えたスニペット」と取り違えて台帳ごと消す（実際に踏んだ）
- **鮮度検査** — コードを変えたら赤くなり、URL がずれても赤くなる
- **撮影の段取り** — 本番のリクエストを**起動前**に置く（#784）。絵そのものは GPU が
  要るので撮れないが、「いつリクエストを置くか」は偽の Probe で確かめられる。ここが
  ずれると、動きのスニペットは実行ごとに違う位相から撮れて撮り直しが毎回別物になる
"""

import importlib.util
import io
import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "generate-reference-shots.py"
_spec = importlib.util.spec_from_file_location("generate_reference_shots", _SCRIPT)
shots = importlib.util.module_from_spec(_spec)
sys.modules["generate_reference_shots"] = shots
_spec.loader.exec_module(shots)


SOURCE = '''// MARK: - Shapes

extension Sketch {

    /// 円を描画します。
    ///
    /// - Parameter diameter: 円の直径。
    ///
    /// ### 実行結果
    ///
    /// <!-- reference-shot -->
    ///
    /// ```swift
    /// background(24)
    /// circle(width / 2, height / 2, 200)
    /// ```
    public func circle(_ x: Float, _ y: Float, _ diameter: Float) {
        context.circle(x, y, diameter)
    }

    /// 説明のためだけのコード（印が無いので撮らない）。
    ///
    /// ```swift
    /// noLoop()
    /// ```
    public func noLoop() {
        context.noLoop()
    }

    /// 円弧を描画します。
    ///
    /// ### 実行結果
    ///
    /// <!-- reference-shot -->
    ///
    /// ```swift
    /// arc(0, 0, 10, 10, 0, 1)
    /// ```
    @discardableResult
    public func arc(
        _ x: Float, _ y: Float,
        _ mode: ArcMode = .default
    ) -> Bool {
        true
    }
}
'''


class ReferenceShotsTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.work = Path(tempfile.mkdtemp(prefix="reference-shots-test-"))
        self.source = self.work / "Sketch+Shapes.swift"
        self.source.write_text(SOURCE, encoding="utf-8")
        # モジュールはリポジトリルート基準でキーを作る。テストの一時ディレクトリを
        # ルートに見せかけて、実ファイルに触らずに全経路を通す。
        self._repo_root = shots.REPO_ROOT
        shots.REPO_ROOT = self.work

    def tearDown(self) -> None:
        shots.REPO_ROOT = self._repo_root

    def extract(self) -> list:
        return shots.extract(self.source)

    # --- 抽出 ---------------------------------------------------------------

    def test_extracts_only_marked_fences(self):
        """印の無いフェンス（説明用）は撮影対象にならない。"""
        found = self.extract()
        self.assertEqual(
            [snippet.symbol for snippet in found],
            ["circle(_:_:_:)", "arc(_:_:_:)"],
        )

    def test_symbol_matches_docc_page_name(self):
        """宣言から DocC のページ名と同じ表記を作る（複数行・属性つきも）。"""
        circle, arc = self.extract()
        self.assertEqual(circle.symbol, "circle(_:_:_:)")
        self.assertEqual(circle.key, "Sketch+Shapes.swift::circle(_:_:_:)")
        # @discardableResult を挟んでも、宣言が複数行でも読める
        self.assertEqual(arc.symbol, "arc(_:_:_:)")

    def test_snippet_code_is_the_draw_body(self):
        circle, _ = self.extract()
        self.assertEqual(
            circle.code,
            ["background(24)", "circle(width / 2, height / 2, 200)"],
        )

    def test_missing_fence_is_an_error(self):
        self.source.write_text(
            "extension Sketch {\n"
            "    /// <!-- reference-shot -->\n"
            "    public func circle() {}\n"
            "}\n",
            encoding="utf-8",
        )
        with self.assertRaises(shots.ShotError):
            self.extract()

    # --- 生成パッケージのターゲット名 ---------------------------------------

    def _target(self, symbol: str) -> str:
        return shots.Snippet(self.source, symbol, [], 0, 0, "    ").target

    def test_overloads_get_distinct_targets(self):
        """引数の数が違うオーバーロードは別ターゲットになる。

        同じ名前になると生成パッケージが `duplicate target named ...` で
        ビルドできず、そのファイルの撮影が丸ごと止まる。
        """
        self.assertEqual(self._target("rect(_:_:_:_:)"), "Shot_Sketch_Shapes_rect_4")
        self.assertEqual(self._target("rect(_:_:_:_:_:)"), "Shot_Sketch_Shapes_rect_5")
        self.assertEqual(
            self._target("rect(_:_:_:_:_:_:_:_:)"), "Shot_Sketch_Shapes_rect_8"
        )

    def test_target_keeps_argument_labels(self):
        """外部ラベルも名前に入る（引数の数が同じオーバーロードのため）。"""
        self.assertEqual(
            self._target("linearGradient(_:_:_:_:_:_:axis:)"),
            "Shot_Sketch_Shapes_linearGradient_7_axis",
        )
        self.assertEqual(self._target("push()"), "Shot_Sketch_Shapes_push_0")

    # --- 指紋 ---------------------------------------------------------------

    def test_fingerprint_follows_code_and_settings(self):
        circle, _ = self.extract()
        plain = circle.fingerprint({})
        moved = circle.fingerprint({circle.key: {"width": 800}})
        self.assertNotEqual(plain, moved, "撮影設定を変えたら撮り直しが要る")
        self.assertEqual(plain, circle.fingerprint({}))

    # --- 書き戻し -----------------------------------------------------------

    def test_rewrite_builds_a_row_then_stays_idempotent(self):
        """既定は p5.js と同じ「絵が左・コードが右」の横並び。"""
        circle, _ = self.extract()
        ledger = {circle.key: {"url": "https://i.gyazo.com/aaa.png"}}

        touched = shots.rewrite_sources([circle], ledger, {})
        self.assertEqual(touched, [self.source])
        text = self.source.read_text(encoding="utf-8")
        self.assertIn("/// @Row {", text)
        self.assertIn("/// ![circle(_:_:_:) の実行結果](https://i.gyazo.com/aaa.png)", text.replace("   ", ""))
        # 絵の列がコードの列より先（＝左）に来る
        self.assertLess(text.index("aaa.png"), text.index("```swift"))

        # 2 回目は差分が出ない（位置で対応づけているので自己修復的）
        self.assertEqual(shots.rewrite_sources(self.extract(), ledger, {}), [])
        self.assertEqual(self.source.read_text(encoding="utf-8"), text)

    def test_rewrite_keeps_the_code_verbatim_without_creeping_indent(self):
        """コードは人が書いたもの。列に入れても字下げが積み増されない。"""
        circle, _ = self.extract()
        ledger = {circle.key: {"url": "https://i.gyazo.com/aaa.png"}}
        for _ in range(3):
            shots.rewrite_sources(self.extract(), ledger, {})
        again = self.extract()[0]
        self.assertEqual(
            again.code, ["background(24)", "circle(width / 2, height / 2, 200)"]
        )

    def test_layout_stack_puts_the_code_first(self):
        circle, _ = self.extract()
        ledger = {circle.key: {"url": "https://i.gyazo.com/aaa.png"}}
        config = {circle.key: {"layout": "stack"}}

        shots.rewrite_sources([circle], ledger, config)
        text = self.source.read_text(encoding="utf-8")
        self.assertNotIn("@Row", text)
        self.assertLess(text.index("```swift"), text.index("aaa.png"))

        # 横並びへ戻せる（レイアウトの往復でコードが壊れない）
        shots.rewrite_sources(self.extract(), ledger, {})
        back = self.extract()[0]
        self.assertIn("@Row", self.source.read_text(encoding="utf-8"))
        self.assertEqual(back.code, circle.code)

    def _with_first_code_line(self, line: str) -> object:
        self.source.write_text(
            self.source.read_text(encoding="utf-8").replace(
                "    /// background(24)\n", f"    /// {line}\n", 1
            ),
            encoding="utf-8",
        )
        return self.extract()[0]

    def test_long_lines_are_refused_in_a_row_but_allowed_when_stacked(self):
        """列に収まらないコードは止める（DocC は折り返さず、はみ出しは切れる）。

        上限は「DocC がまだ列を縦に折らない一番狭い幅」から実測で決めた値なので、
        テスト側も実測に沿った具体的な長さで確かめる（定数から行を作ると、定数を
        変えたときにテストごと一緒に動いてしまい、何も検出しなくなる）。
        """
        self.assertLess(shots.MAX_ROW_LINE, 60, "上限を緩めるなら実測をやり直すこと")
        circle = self._with_first_code_line("line(80, 70, 400, 70) // " + "x" * 35)
        with self.assertRaises(shots.ShotError):
            circle.layout({})
        self.assertEqual(circle.layout({circle.key: {"layout": "stack"}}), "stack")

    def test_a_line_exactly_at_the_budget_is_allowed(self):
        circle = self._with_first_code_line("x" * shots.MAX_ROW_LINE)
        self.assertEqual(circle.layout({}), "row")

    def test_an_unknown_layout_is_an_error(self):
        circle, _ = self.extract()
        with self.assertRaises(shots.ShotError):
            circle.layout({circle.key: {"layout": "sidebar"}})

    def test_layout_is_not_part_of_the_fingerprint(self):
        """並べ方を変えても撮り直しにはならない（絵は変わらないので）。"""
        circle, _ = self.extract()
        self.assertEqual(
            circle.fingerprint({}),
            circle.fingerprint({circle.key: {"layout": "stack"}}),
        )

    def test_an_unknown_symmetric_value_is_an_error(self):
        circle, _ = self.extract()
        with self.assertRaises(shots.ShotError):
            circle.symmetric({circle.key: {"symmetric": "diagonal"}})

    def test_symmetric_is_not_part_of_the_fingerprint(self):
        """「対称でよい」の申告は撮り直しを起こさない（絵は変わらないので）。

        `layout` と同じ不変条件。これを破ると、申告を足した日にも外した日にも全点の
        指紋が動き、絵が 1 枚も変わっていないのに 58 点の撮り直しが要る（#784 の `settle`
        で実際に踏んだ）。
        """
        circle, _ = self.extract()
        for value in shots.SYMMETRIES:
            self.assertEqual(
                circle.fingerprint({}),
                circle.fingerprint({circle.key: {"symmetric": value}}),
                f"symmetric: {value} が指紋を動かしている",
            )

    def test_a_flip_match_above_the_threshold_warns(self):
        """反転と見分けが付かない絵は、軸ごとに警告になる（#985）。

        しきい値は台帳 58 点の実測から決めた値なので、テスト側も実測に沿った具体的な
        値で確かめる（定数から作ると、しきい値を動かしたときテストごと一緒に動いて
        何も検出しなくなる）。#923 の `ortho` は直す前が上下反転と完全一致、
        `perspective` は 58.7 dB、直した後は 16.7 / 20.5 dB だった。
        """
        self.assertLess(shots.FLIP_PSNR_WARN_DB, 43.5, "40 dB より上げると radialGradient 帯に入る")
        self.assertGreater(shots.FLIP_PSNR_WARN_DB, 37.0, "40 dB より下げると通常の図形を拾う")
        circle, _ = self.extract()
        measured = {"vflip": float("inf"), "hflip": 58.66}
        warnings = shots.symmetry_warnings(
            circle, Path("still.png"), None, measure=lambda _, flip: measured[flip]
        )
        self.assertEqual(len(warnings), 2)
        self.assertIn("上下", warnings[0])
        self.assertIn("完全一致", warnings[0])
        self.assertIn("左右", warnings[1])
        self.assertIn("58.7 dB", warnings[1])

    def test_an_asymmetric_shot_is_silent(self):
        circle, _ = self.extract()
        warnings = shots.symmetry_warnings(
            circle, Path("still.png"), None, measure=lambda _f, _a: 20.46
        )
        self.assertEqual(warnings, [])

    def test_an_unmeasurable_shot_says_so_instead_of_going_quiet(self):
        """ffmpeg が無くて測れないときは、黙らずに note を返す。

        警告を出すための仕組みが、測れないときに無言で「異常なし」と見分けが
        付かなくなるのが一番危ない（実際 CI には ffmpeg が入っていない）。
        """
        circle, _ = self.extract()
        notes = shots.symmetry_warnings(
            circle, Path("still.png"), None, measure=lambda _f, _a: None
        )
        self.assertEqual(len(notes), 1)
        self.assertIn("飛ばした", notes[0])
        self.assertIn("ffmpeg", notes[0])

    def test_flip_psnr_returns_none_without_ffmpeg(self):
        """ffmpeg の有無を持つのは flip_psnr（計測経路を 1 本にする）。"""
        saved = shots.shutil.which
        shots.shutil.which = lambda _name: None
        try:
            self.assertIsNone(shots.flip_psnr(Path("still.png"), "vflip"))
        finally:
            shots.shutil.which = saved

    def test_a_declared_axis_is_silenced_but_the_other_is_not(self):
        circle, _ = self.extract()
        measure = lambda _f, _a: float("inf")  # noqa: E731
        vertical = shots.symmetry_warnings(
            circle, Path("still.png"), "vertical", measure=measure
        )
        self.assertEqual(len(vertical), 1)
        self.assertIn("左右", vertical[0])
        self.assertEqual(
            shots.symmetry_warnings(circle, Path("still.png"), "both", measure=measure),
            [],
        )

    def test_motion_shows_only_the_gif(self):
        circle, _ = self.extract()
        shots.rewrite_sources(
            [circle],
            {
                circle.key: {
                    "url": "https://i.gyazo.com/still.png",
                    "motion": {"url": "https://i.gyazo.com/moving.gif"},
                }
            },
            {},
        )
        text = self.source.read_text(encoding="utf-8")
        self.assertIn("moving.gif", text)
        self.assertNotIn("still.png", text)
        self.assertIn("の実行結果（動き）", text)

    def test_rewrite_replaces_a_stale_url(self):
        circle, _ = self.extract()
        shots.rewrite_sources([circle], {circle.key: {"url": "https://i.gyazo.com/old.png"}}, {})
        shots.rewrite_sources(
            self.extract(), {circle.key: {"url": "https://i.gyazo.com/new.png"}}, {}
        )
        text = self.source.read_text(encoding="utf-8")
        self.assertNotIn("old.png", text)
        self.assertIn("](https://i.gyazo.com/new.png)", text)
        # 宣言が生成物領域に押し流されていない
        self.assertIn("public func circle(_ x: Float", text)

    def test_prose_after_the_marker_is_refused(self):
        """印から下は生成物領域。人の文章があれば、消す前に止める。"""
        text = self.source.read_text(encoding="utf-8").replace(
            "    /// <!-- reference-shot -->\n",
            "    /// <!-- reference-shot -->\n    ///\n    /// これは消えてはいけない説明。\n",
        )
        self.source.write_text(text, encoding="utf-8")
        with self.assertRaises(shots.ShotError):
            self.extract()

    # --- 台帳の掃除 ---------------------------------------------------------

    def test_only_filter_does_not_prune_the_ledger(self):
        """`--only` で絞った実行が、視界の外のエントリを消さない。

        絞ったまま「スニペットに対応しないエントリ」を掃除すると、他のシンボルの
        URL を台帳ごと失う（撮り直し = 全点の再アップロードになる）。
        """
        circle, arc = self.extract()
        ledger = {
            circle.key: {"url": "https://i.gyazo.com/circle.png", "snippetHash": "x"},
            arc.key: {"url": "https://i.gyazo.com/arc.png", "snippetHash": "y"},
            "Sources/Gone.swift::gone()": {"url": "https://i.gyazo.com/gone.png"},
        }
        shots.MANIFEST = self.work / "manifest.json"

        kept = dict(ledger)
        shots.prune_orphans(kept, [circle], prune=False)
        self.assertEqual(set(kept), set(ledger), "絞った実行では掃除しない")

        swept = dict(ledger)
        shots.prune_orphans(swept, [circle, arc], prune=True)
        self.assertEqual(set(swept), {circle.key, arc.key})

    # --- 鮮度検査 -----------------------------------------------------------

    def test_check_detects_stale_and_drifted(self):
        circle, arc = self.extract()
        config = {}
        ledger = {
            circle.key: {
                "url": "https://i.gyazo.com/circle.png",
                "snippetHash": circle.fingerprint(config),
            },
            arc.key: {
                "url": "https://i.gyazo.com/arc.png",
                "snippetHash": arc.fingerprint(config),
            },
        }
        shots.rewrite_sources([circle, arc], ledger, config)
        self.assertEqual(shots.check(self.extract(), ledger, config), 0)

        # コードを変えたら赤くなる
        stale = dict(ledger)
        stale[circle.key] = {**ledger[circle.key], "snippetHash": "changed"}
        self.assertEqual(shots.check(self.extract(), stale, config), 1)

        # 本文の URL が台帳とずれても赤くなる
        drifted = json.loads(json.dumps(ledger))
        drifted[circle.key]["url"] = "https://i.gyazo.com/somewhere-else.png"
        self.assertEqual(shots.check(self.extract(), drifted, config), 1)

    def test_check_reports_missing_image(self):
        self.assertEqual(shots.check(self.extract(), {}, {}), 1)


class FakeSketch:
    """`swift run <target>` の代わり。`request.json` に応えるだけの最小 Probe。

    **置かれたリクエストが何であっても同じように応える**ので、テストの主張
    （＝どのリクエストを、いつ置いたか）だけが結果を分ける。撮影側が下見を挟んでも
    挟まなくても素通しするため、直っていない実装はタイムアウトではなく主張の失敗で
    落ちる。
    """

    POLL_SEC = 0.01

    def __init__(self, probe_dir: Path) -> None:
        self.probe_dir = probe_dir
        # 起動時点と終了時点の request.json。撮影側が起動後に置き直したかが分かる。
        self.request_at_launch = self._read_request()
        self.request_at_exit: dict | None = None
        self.returncode: int | None = None
        self.stdin = None
        self.stderr = None
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._serve, daemon=True)
        self._thread.start()

    # --- subprocess.Popen として振る舞う ---------------------------------------

    def poll(self) -> int | None:
        return self.returncode

    def terminate(self) -> None:
        self.request_at_exit = self._read_request()
        self._stop.set()
        self.returncode = 0

    def kill(self) -> None:
        self.terminate()

    def wait(self, timeout: float | None = None) -> int | None:
        self._thread.join(timeout)
        return self.returncode

    # --- 最小 Probe -----------------------------------------------------------

    def _read_request(self) -> dict | None:
        path = self.probe_dir / "request.json"
        if not path.is_file():
            return None
        return json.loads(path.read_text(encoding="utf-8"))

    def _serve(self) -> None:
        handled: set[str] = set()
        while not self._stop.wait(self.POLL_SEC):
            request = self._read_request()
            if request is None or request["id"] in handled:
                continue
            handled.add(request["id"])
            if (request.get("frames") or 1) >= 2:
                self._write_sequence(request)
            else:
                self._write_frame(request)

    def _write_frame(self, request: dict) -> None:
        current = self.probe_dir / "current"
        current.mkdir(parents=True, exist_ok=True)
        (current / "frame.png").write_bytes(b"png")
        (current / "frame.json").write_text(
            json.dumps({"id": request["id"], "size": {"width": 480, "height": 360}}),
            encoding="utf-8",
        )

    def _write_sequence(self, request: dict) -> None:
        directory = self.probe_dir / "current/sequence"
        directory.mkdir(parents=True, exist_ok=True)
        frames = [
            {"index": index, "file": f"frame.{index:04d}.png"}
            for index in range(request["frames"])
        ]
        # 完了規約: sequence.json が最後（CONTRACT.md 契約点 4）。
        (directory / "sequence.json").write_text(
            json.dumps(
                {
                    "id": request["id"],
                    "frameCount": len(frames),
                    "every": request.get("every", 1),
                    "size": {"width": 480, "height": 360},
                    "frames": frames,
                }
            ),
            encoding="utf-8",
        )


class DeadSketch:
    """起動直後に落ちたスケッチ。撮影側が待ち続けずに諦めることの確認用。"""

    def __init__(self, message: str = "Fatal error: no Metal device") -> None:
        self.returncode = 1
        self.stdin = None
        self.stderr = io.StringIO(message)

    def poll(self) -> int:
        return self.returncode

    def terminate(self) -> None:
        pass

    def kill(self) -> None:
        pass

    def wait(self, timeout: float | None = None) -> int:
        return self.returncode


class CaptureTestCase(unittest.TestCase):
    """撮影の段取り（#784）。

    動きのスニペットは `rotate(Float(frameCount) * 0.02)` のように frameCount で
    駆動する。撮り始めのフレームが実行ごとに変わると全フレームの位相がずれ、同じ
    コードを撮り直すだけで別の GIF になる（＝ #781 の鮮度照合が成り立たない）。
    撮り始めを固定する唯一の方法は、本番のリクエストを**起動前**に置くこと。
    """

    def setUp(self) -> None:
        self.work = Path(tempfile.mkdtemp(prefix="reference-shots-capture-"))
        self._saved = {
            "REPO_ROOT": shots.REPO_ROOT,
            "WORK_DIR": shots.WORK_DIR,
            "STAGING_DIR": shots.STAGING_DIR,
            "CAPTURE_TIMEOUT_SEC": shots.CAPTURE_TIMEOUT_SEC,
            "POLL_INTERVAL_SEC": shots.POLL_INTERVAL_SEC,
            "collect_sequence": shots.collect_sequence,
            "flip_psnr": shots.flip_psnr,
            "Popen": shots.subprocess.Popen,
        }
        shots.REPO_ROOT = self.work
        shots.WORK_DIR = self.work / "build"
        shots.STAGING_DIR = shots.WORK_DIR / "staging"
        # 段取りが崩れていても待たずに落とす（既定は 120 秒）。
        shots.CAPTURE_TIMEOUT_SEC = 5.0
        shots.POLL_INTERVAL_SEC = 0.01
        # 連番から GIF を作るところは ffmpeg が要るので、ここでは通らない。
        shots.collect_sequence = lambda *args, **kwargs: {"width": 480, "height": 360}
        # 反転一致の計測も ffmpeg が要る（偽の PNG に中身は無い）。既定は「対称でない」。
        # flip_psnr は ffmpeg の有無まで受け持つので、これを差し替えれば
        # ffmpeg の無い CI でも判定ロジックそのものを検査できる。
        self.measured = 20.46
        shots.flip_psnr = lambda *args, **kwargs: self.measured

        self.probe_dir = shots.WORK_DIR / ".metaphor/probe"
        self.launched: list[FakeSketch] = []
        shots.subprocess.Popen = self._popen

    def tearDown(self) -> None:
        shots.REPO_ROOT = self._saved["REPO_ROOT"]
        shots.WORK_DIR = self._saved["WORK_DIR"]
        shots.STAGING_DIR = self._saved["STAGING_DIR"]
        shots.CAPTURE_TIMEOUT_SEC = self._saved["CAPTURE_TIMEOUT_SEC"]
        shots.POLL_INTERVAL_SEC = self._saved["POLL_INTERVAL_SEC"]
        shots.collect_sequence = self._saved["collect_sequence"]
        shots.flip_psnr = self._saved["flip_psnr"]
        shots.subprocess.Popen = self._saved["Popen"]

    def _popen(self, *args, **kwargs) -> FakeSketch:
        process = FakeSketch(self.probe_dir)
        self.launched.append(process)
        return process

    def _snippet(self) -> object:
        return shots.Snippet(
            self.work / "Sources/MetaphorCore/Sketch/Sketch+Shapes.swift",
            "rotate(_:)",
            ["rotate(Float(frameCount) * 0.02)"],
            0,
            0,
            "    ",
        )

    def test_motion_places_the_real_request_before_launch(self):
        """動きでも起動前に本番を置く（下見を待って置き直さない）。

        置き直すまでのあいだもスケッチは進むので、起動後に置くと撮り始めの
        frameCount が実行ごとに変わる。
        """
        snippet = self._snippet()
        settings = snippet.settings(
            {snippet.key: {"motion": {"frames": 6, "every": 2, "fps": 15}}}
        )
        shots.capture(snippet, settings)

        self.assertEqual(len(self.launched), 1)
        launch = self.launched[0].request_at_launch
        self.assertIsNotNone(launch, "起動前に request.json が置かれていない")
        self.assertEqual(launch["id"], f"reference-shot-{snippet.target}")
        self.assertEqual(launch["frames"], 6, "起動前に置いたのが連続キャプチャでない")
        self.assertEqual(launch["every"], 2)
        # 起動後に置き直していない（置き直すと撮り始めが実行ごとに変わる）。
        self.assertEqual(self.launched[0].request_at_exit, launch)

    def test_capture_settings_have_no_wall_clock_delay(self):
        """撮影設定に実時間の待ちを持たない（持つと撮り始めがずれる）。

        `settle` 秒の待ちがあった頃は、待っているあいだに進んだフレーム数が
        実行ごとに違い、動きのスニペットが毎回別の絵になっていた（#784）。
        """
        snippet = self._snippet()
        self.assertEqual(
            set(snippet.settings({})), {"width", "height"}
        )

    def test_still_places_the_real_request_before_launch(self):
        """静止画も起動前（noLoop は最初の 1 フレームしか描かない）。"""
        snippet = self._snippet()
        entry = shots.capture(snippet, snippet.settings({}))

        launch = self.launched[0].request_at_launch
        self.assertEqual(launch["id"], f"reference-shot-{snippet.target}")
        self.assertNotIn("frames", launch, "静止画に連続キャプチャを頼んでいる")
        self.assertEqual(entry, {"width": 480, "height": 360})
        self.assertTrue((shots.STAGING_DIR / f"{snippet.target}.png").is_file())

    def test_capture_surfaces_the_flip_warning(self):
        """反転と見分けの付かない絵は、撮った直後に警告として出る（#985）。

        撮影は止めない（対称なのが正しい絵は普通にある）。`shots.config.json` で
        「対称でよい」と申告してあるものは黙る。
        """
        self.measured = float("inf")
        snippet = self._snippet()

        printed = io.StringIO()
        stdout, sys.stdout = sys.stdout, printed
        try:
            entry = shots.capture(snippet, snippet.settings({}))
        finally:
            sys.stdout = stdout
        self.assertEqual(entry, {"width": 480, "height": 360}, "警告は撮影を止めない")
        self.assertIn("上下反転と見分けが付きません", printed.getvalue())
        self.assertIn("左右反転と見分けが付きません", printed.getvalue())

        printed = io.StringIO()
        stdout, sys.stdout = sys.stdout, printed
        try:
            shots.capture(snippet, snippet.settings({}), "both")
        finally:
            sys.stdout = stdout
        self.assertNotIn("見分けが付きません", printed.getvalue())

    def test_a_sketch_that_dies_is_reported_with_its_stderr(self):
        """起動に失敗したら、タイムアウトを待たずに理由ごと止まる。"""
        shots.subprocess.Popen = lambda *args, **kwargs: DeadSketch()
        snippet = self._snippet()
        with self.assertRaises(shots.ShotError) as raised:
            shots.capture(snippet, snippet.settings({}))
        self.assertIn("exit 1", str(raised.exception))
        self.assertIn("no Metal device", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
