#!/usr/bin/env python3
"""Unit tests for scripts/translate-reference.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

確かめるのは、翻訳エンジンの呼び出し（ネットワークが要る）を除いた 4 つ。

- **翻訳する / しないの線引き** — 日本語の説明（#334 が Core を英語化するまで残る）と、
  記号だけの断片を訳しにいかないこと。ここが狂うと移行期の日本語版が二重翻訳で崩れる
- **インライン列の往復** — `Sets the ⟦0⟧ color.` に畳んで訳し、元の位置へインラインコードを
  戻せること。プレースホルダが訳文から消えていたら**訳を捨てて原文を残す**こと
- **触ってはいけない場所** — `codeListing`（コード例）と宣言が翻訳対象に入らないこと。
  render JSON を訳す方式を選んだ理由そのものなので、退行したら方式が崩れる
- **鮮度検査** — 台帳に訳が無ければ `--check` が赤くなり、入れたら緑になること
"""

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "translate-reference.py"
_spec = importlib.util.spec_from_file_location("translate_reference", _SCRIPT)
translate = importlib.util.module_from_spec(_spec)
sys.modules["translate_reference"] = translate
_spec.loader.exec_module(translate)


def render_document() -> dict:
    """`docc convert` が吐く render JSON の、翻訳に関係する部分だけを写したもの。"""
    return {
        "abstract": [
            {"type": "text", "text": "Sets the "},
            {"type": "codeVoice", "code": "fill"},
            {"type": "text", "text": " color."},
        ],
        "primaryContentSections": [
            {
                "kind": "content",
                "content": [
                    {"type": "heading", "level": 2, "anchor": "Overview", "text": "Overview"},
                    {
                        "type": "paragraph",
                        "inlineContent": [{"type": "text", "text": "Draws a circle."}],
                    },
                    {
                        "type": "codeListing",
                        "syntax": "swift",
                        "code": ["background(240)", "circle(0, 0, 200)"],
                    },
                    {
                        "type": "paragraph",
                        "inlineContent": [{"type": "text", "text": "円を描画します。"}],
                    },
                ],
            }
        ],
    }


class TranslatableTests(unittest.TestCase):
    """何を訳しにいくかの線引き。"""

    def test_plain_english_is_translatable(self):
        self.assertTrue(translate.is_translatable("Sets the fill color."))

    def test_japanese_is_left_alone(self):
        # 移行期は Core の説明が日本語のまま。訳しにいくと二重翻訳になる。
        self.assertFalse(translate.is_translatable("円を描画します。"))

    def test_japanese_mixed_with_english_terms_is_left_alone(self):
        # 実際の Core はこの形（型名や API 名だけがラテン文字）。ラテン文字を含むので
        # 日本語判定が無いと翻訳対象に紛れ込む。
        self.assertFalse(
            translate.is_translatable("SwiftUI ビュー階層内で Metal レンダリングを表示します。")
        )

    def test_symbols_only_are_left_alone(self):
        self.assertFalse(translate.is_translatable("."))
        self.assertFalse(translate.is_translatable("   "))
        self.assertFalse(translate.is_translatable(""))

    def test_placeholder_only_is_left_alone(self):
        # インラインコード単体。訳す中身が無い。
        self.assertFalse(translate.is_translatable("⟦0⟧"))

    def test_sentence_with_placeholders_is_translatable(self):
        self.assertTrue(translate.is_translatable("⟦0⟧ is ⟦1⟧."))


class InlineRoundTripTests(unittest.TestCase):
    """インライン列を 1 文へ畳み、訳文から組み直す。"""

    def test_serialize_replaces_non_text_with_markers(self):
        items = [
            {"type": "text", "text": "Sets the "},
            {"type": "codeVoice", "code": "fill"},
            {"type": "text", "text": " color."},
        ]
        text, slots = translate.serialize_inline(items)
        self.assertEqual(text, "Sets the ⟦0⟧ color.")
        self.assertEqual(slots, [{"type": "codeVoice", "code": "fill"}])

    def test_deserialize_puts_nodes_back(self):
        slots = [{"type": "codeVoice", "code": "fill"}]
        rebuilt = translate.deserialize_inline("⟦0⟧ の色を設定します。", slots)
        self.assertEqual(
            rebuilt,
            [
                {"type": "codeVoice", "code": "fill"},
                {"type": "text", "text": " の色を設定します。"},
            ],
        )

    def test_deserialize_rejects_lost_placeholder(self):
        # 翻訳器がマーカーを落とした訳は使わない（インラインコードが消えるため）。
        slots = [{"type": "codeVoice", "code": "fill"}]
        self.assertIsNone(translate.deserialize_inline("色を設定します。", slots))

    def test_deserialize_rejects_invented_placeholder(self):
        slots = [{"type": "codeVoice", "code": "fill"}]
        self.assertIsNone(translate.deserialize_inline("⟦0⟧ と ⟦1⟧ を設定します。", slots))


class SlotDiscoveryTests(unittest.TestCase):
    """訳す場所を見つける。触ってはいけない場所を見つけない。"""

    def test_finds_abstract_paragraph_and_heading(self):
        document = render_document()
        found = {
            translate.source_of(container, key)[0]
            for container, key in translate.iter_translatable_slots(document)
            if translate.source_of(container, key) is not None
        }
        self.assertIn("Sets the ⟦0⟧ color.", found)
        self.assertIn("Draws a circle.", found)
        self.assertIn("Overview", found)

    def test_never_touches_code_listings(self):
        document = render_document()
        for container, key in translate.iter_translatable_slots(document):
            self.assertNotEqual(
                container.get("type"),
                "codeListing",
                "コード例が翻訳対象に入った（render JSON を訳す方式の前提が崩れる）",
            )
            self.assertNotEqual(key, "code")


class ApplyLedgerTests(unittest.TestCase):
    """台帳を当てて日本語版の render JSON を作る。"""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.docs_dir = Path(self._tmp.name) / "docs"
        target = self.docs_dir / "data" / "documentation" / "metaphor"
        target.mkdir(parents=True)
        self.page = target / "fill.json"
        self.page.write_text(json.dumps(render_document()), encoding="utf-8")

    def tearDown(self):
        self._tmp.cleanup()

    def ledger(self, **pairs: str) -> dict:
        return {
            translate.text_key(english): {"en": english, "ja": japanese}
            for english, japanese in pairs.items()
        }

    def test_replaces_translated_text_and_keeps_code(self):
        entries = {
            translate.text_key("Sets the ⟦0⟧ color."): {
                "en": "Sets the ⟦0⟧ color.",
                "ja": "⟦0⟧ の色を設定します。",
            }
        }
        replaced, _, broken = translate.apply_ledger(self.docs_dir, entries)
        self.assertEqual(replaced, 1)
        self.assertEqual(broken, 0)

        written = json.loads(self.page.read_text(encoding="utf-8"))
        self.assertEqual(
            written["abstract"],
            [
                {"type": "codeVoice", "code": "fill"},
                {"type": "text", "text": " の色を設定します。"},
            ],
        )
        # コード例は原文のまま。
        listing = written["primaryContentSections"][0]["content"][2]
        self.assertEqual(listing["code"], ["background(240)", "circle(0, 0, 200)"])

    def test_keeps_anchor_when_heading_is_translated(self):
        entries = {translate.text_key("Overview"): {"en": "Overview", "ja": "概要"}}
        translate.apply_ledger(self.docs_dir, entries)

        heading = json.loads(self.page.read_text(encoding="utf-8"))[
            "primaryContentSections"
        ][0]["content"][0]
        self.assertEqual(heading["text"], "概要")
        self.assertEqual(heading["anchor"], "Overview", "アンカーを訳すとページ内リンクが切れる")

    def test_untranslated_text_is_left_in_english(self):
        replaced, left, _ = translate.apply_ledger(self.docs_dir, {})
        self.assertEqual(replaced, 0)
        self.assertGreater(left, 0)

        written = json.loads(self.page.read_text(encoding="utf-8"))
        self.assertEqual(written["abstract"][0], {"type": "text", "text": "Sets the "})

    def test_broken_translation_is_discarded(self):
        entries = {
            translate.text_key("Sets the ⟦0⟧ color."): {
                "en": "Sets the ⟦0⟧ color.",
                "ja": "色を設定します。",  # マーカーが落ちている
            }
        }
        replaced, _, broken = translate.apply_ledger(self.docs_dir, entries)
        self.assertEqual(broken, 1)

        written = json.loads(self.page.read_text(encoding="utf-8"))
        self.assertEqual(
            written["abstract"][1],
            {"type": "codeVoice", "code": "fill"},
            "壊れた訳を当てるとインラインコードが消える",
        )

    def test_check_goes_green_once_the_ledger_is_filled(self):
        sources = translate.collect_sources(self.docs_dir)
        self.assertTrue(translate.missing_keys(sources, {}))

        entries = {key: {"en": text, "ja": "訳"} for key, text in sources.items()}
        self.assertFalse(translate.missing_keys(sources, entries))


if __name__ == "__main__":
    unittest.main()
