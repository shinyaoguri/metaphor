#!/usr/bin/env python3
"""Unit tests for scripts/check-doc-comment-language.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

守りたいのは「公開 API の doc コメントが日本語へ戻らないこと」（Issue #334）。
PR #361 / #365 が一度英語化した周辺モジュールに 93 行の日本語が静かに戻っていた
のがこの検査を足した理由なので、リポジトリ実体を見るテスト（`TestRepositoryMatchesAllowlist`）
が本命。判定規則のテストはその周りを固める。

特に大事なのは**偽陽性を出さないこと** — `//` の通常コメントや、生成物である
reference-shot の alt テキストで落ちると、無関係なモジュールを ALLOWLIST に足す
圧力が生まれて守りが空洞化する。
"""

import importlib.util
import sys
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "check-doc-comment-language.py"
_spec = importlib.util.spec_from_file_location("check_doc_comment_language", _SCRIPT)
check = importlib.util.module_from_spec(_spec)
sys.modules["check_doc_comment_language"] = check
_spec.loader.exec_module(check)

ROOT = Path(__file__).resolve().parents[2]


class TestDetectsJapanese(unittest.TestCase):
    def test_flags_a_japanese_doc_line(self):
        found = check.japanese_doc_lines("/// 円を描きます。\nfunc circle() {}\n")
        self.assertEqual([n for n, _ in found], [1])

    def test_flags_katakana_and_kanji_too(self):
        """ひらがな以外だけの行も拾う（`/// テクスチャ生成` のような見出し）。"""
        self.assertEqual(len(check.japanese_doc_lines("/// テクスチャ生成\n")), 1)
        self.assertEqual(len(check.japanese_doc_lines("/// 生成物\n")), 1)

    def test_flags_a_mixed_line(self):
        """英語の中に日本語が混ざる行も対象（訳し残し）。"""
        found = check.japanese_doc_lines("/// Draws a circle. 塗りは `fill()` に従う。\n")
        self.assertEqual(len(found), 1)

    def test_reports_the_line_number(self):
        text = "/// Draws a circle.\n///\n/// 塗りは `fill()` に従う。\nfunc circle() {}\n"
        self.assertEqual([n for n, _ in check.japanese_doc_lines(text)], [3])


class TestIgnoresWhatItShould(unittest.TestCase):
    def test_ignores_english_doc_comments(self):
        self.assertEqual(check.japanese_doc_lines("/// Draws a circle.\n"), [])

    def test_ignores_ordinary_comments(self):
        """`//` の通常コメントは対象外 — 実装の意図を書いた日本語は残してよい。"""
        self.assertEqual(check.japanese_doc_lines("// 塗りは fill() に従う\n"), [])
        self.assertEqual(check.japanese_doc_lines("// MARK: - 図形\n"), [])

    def test_ignores_japanese_in_code(self):
        """文字列リテラルの日本語は doc コメントではない。"""
        self.assertEqual(check.japanese_doc_lines('let s = "円を描く"\n'), [])

    def test_ignores_a_trailing_comment(self):
        """行末コメントは `///` で始まらないので対象外。"""
        self.assertEqual(check.japanese_doc_lines("let r = 10  // 半径\n"), [])

    def test_ignores_everything_after_the_reference_shot_mark(self):
        """印より後ろは make reference-shots の生成物（alt が日本語なのは #1079）。"""
        text = (
            "/// Draws a circle.\n"
            "///\n"
            "/// <!-- reference-shot: circle -->\n"
            "/// ![circle() の実行結果](https://i.gyazo.com/abc.png)\n"
            "/// <!-- /reference-shot -->\n"
            "public func circle() {}\n"
        )
        self.assertEqual(check.japanese_doc_lines(text), [])

    def test_the_generated_block_ends_with_the_doc_comment(self):
        """次の doc コメントブロックまで無視が漏れ続けない。"""
        text = (
            "/// <!-- reference-shot: circle -->\n"
            "/// ![circle() の実行結果](https://i.gyazo.com/abc.png)\n"
            "public func circle() {}\n"
            "\n"
            "/// 四角形を描きます。\n"
            "public func rect() {}\n"
        )
        self.assertEqual([n for n, _ in check.japanese_doc_lines(text)], [5])

    def test_japanese_before_the_mark_is_still_flagged(self):
        """同じブロックでも印より前は本文なので対象。"""
        text = (
            "/// 円を描きます。\n"
            "/// <!-- reference-shot: circle -->\n"
            "/// ![circle() の実行結果](https://i.gyazo.com/abc.png)\n"
        )
        self.assertEqual([n for n, _ in check.japanese_doc_lines(text)], [1])


class TestRepositoryMatchesAllowlist(unittest.TestCase):
    """本命 — リポジトリ実体が ALLOWLIST どおりであること。"""

    def test_check_passes(self):
        self.assertEqual(check.main(), 0)

    def test_allowlist_only_names_real_modules(self):
        """英語化が終わって消えたモジュールが ALLOWLIST に残らないようにする。"""
        modules = {p.name for p in check.SOURCES.iterdir() if p.is_dir()}
        for name in check.ALLOWLIST:
            self.assertIn(name, modules, f"ALLOWLIST に実在しないモジュール: {name}")

    def test_allowlist_entries_are_positive(self):
        """0 になったモジュールは行ごと消す（ALLOWLIST に 0 を残さない）。"""
        for name, (count, reason) in check.ALLOWLIST.items():
            self.assertGreater(count, 0, f"{name} は 0 なので ALLOWLIST から消せます")
            self.assertTrue(reason.strip(), f"{name} に理由が書かれていません")


if __name__ == "__main__":
    unittest.main()
