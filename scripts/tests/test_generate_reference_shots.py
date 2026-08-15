#!/usr/bin/env python3
"""Unit tests for scripts/generate-reference-shots.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

確かめるのは、撮影（GPU・ネットワーク・Gyazo トークンが要る）を除いた 4 つ。

- **抽出** — doc コメントから撮影対象を拾い、宣言から DocC と同じシンボル表記を作る。
  ここが狂うと、別のシンボルのページに絵が出る
- **書き戻し** — 画像行の挿入・更新がべき等（2 回走らせても差分が出ない）
- **台帳の掃除** — `--only` で絞っているときは掃除しない。絞ったまま掃除すると、
  視界の外のエントリを「消えたスニペット」と取り違えて台帳ごと消す（実際に踏んだ）
- **鮮度検査** — コードを変えたら赤くなり、URL がずれても赤くなる
"""

import importlib.util
import json
import sys
import tempfile
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

    # --- 指紋 ---------------------------------------------------------------

    def test_fingerprint_follows_code_and_settings(self):
        circle, _ = self.extract()
        plain = circle.fingerprint({})
        moved = circle.fingerprint({circle.key: {"width": 800}})
        self.assertNotEqual(plain, moved, "撮影設定を変えたら撮り直しが要る")
        self.assertEqual(plain, circle.fingerprint({}))

    # --- 書き戻し -----------------------------------------------------------

    def test_rewrite_inserts_then_stays_idempotent(self):
        circle, _ = self.extract()
        ledger = {circle.key: {"url": "https://i.gyazo.com/aaa.png"}}

        touched = shots.rewrite_sources([circle], ledger)
        self.assertEqual(touched, [self.source])
        text = self.source.read_text(encoding="utf-8")
        self.assertIn("/// ![circle(_:_:_:) の実行結果](https://i.gyazo.com/aaa.png)", text)

        # 2 回目は差分が出ない（位置で対応づけているので自己修復的）
        self.assertEqual(shots.rewrite_sources(self.extract(), ledger), [])
        self.assertEqual(self.source.read_text(encoding="utf-8"), text)

    def test_rewrite_replaces_stale_url_and_adds_motion(self):
        circle, _ = self.extract()
        shots.rewrite_sources([circle], {circle.key: {"url": "https://i.gyazo.com/old.png"}})
        fresh = self.extract()[0]
        shots.rewrite_sources(
            [fresh],
            {
                fresh.key: {
                    "url": "https://i.gyazo.com/new.png",
                    "motion": {"url": "https://i.gyazo.com/new.gif"},
                }
            },
        )
        text = self.source.read_text(encoding="utf-8")
        self.assertNotIn("old.png", text)
        self.assertIn("](https://i.gyazo.com/new.png)", text)
        self.assertIn("](https://i.gyazo.com/new.gif)", text)
        # 宣言が画像行に押し流されていない
        self.assertIn("public func circle(_ x: Float", text)

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
        shots.rewrite_sources([circle, arc], ledger)
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


if __name__ == "__main__":
    unittest.main()
