#!/usr/bin/env python3
"""Unit tests for scripts/check-docs-links.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

守りたいのは `docs/**` の相対リンクと ADR 索引が壊れたら落ちること（Issue #1044）だが、
**素朴な実装は偽陽性を出す**ほうが問題になりやすい。着手時に実際に踏んだ 4 つ（コードとして
書かれたリンク・URL エンコード・記号を除いた跡の空白・見出しのインラインコード）を回帰ケース
として固定する。slug 規則の期待値は GitHub のレンダリング結果（`gh api -H
"Accept: application/vnd.github.html" /repos/.../contents/<path>` が返す `user-content-` の
id）と突き合わせて確かめたもの。
"""

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "check-docs-links.py"
_spec = importlib.util.spec_from_file_location("check_docs_links", _SCRIPT)
check = importlib.util.module_from_spec(_spec)
sys.modules["check_docs_links"] = check
_spec.loader.exec_module(check)


class TempRepo:
    """テスト用の小さなリポジトリを作る。"""

    def __init__(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name).resolve()

    def write(self, relative: str, text: str) -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def cleanup(self) -> None:
        self._tmp.cleanup()


class TestSlugify(unittest.TestCase):
    def test_symbols_are_dropped_without_collapsing_the_spaces(self):
        # `## Amendment 2026-08-23 — 再現性で…` は `-` が 2 個になる（em dash の跡）。
        self.assertEqual(
            check.slugify("Amendment 2026-08-23 — 再現性で保証する範囲・しない範囲"),
            "amendment-2026-08-23--再現性で保証する範囲しない範囲",
        )

    def test_inline_code_keeps_its_contents(self):
        self.assertEqual(
            check.slugify("`frameRate()` sets, `performance` reads"),
            "framerate-sets-performance-reads",
        )

    def test_japanese_brackets_do_not_introduce_a_separator(self):
        # 記号を除いても、元から空白が無いところに `-` は入らない（ADR-0005 で実測）。
        self.assertEqual(
            check.slugify("1. 決定: 規範表をスタイル系の全数へ広げる（`tint` は「2D のみ」）"),
            "1-決定-規範表をスタイル系の全数へ広げるtint-は2d-のみ",
        )

    def test_trailing_space_left_by_a_symbol_becomes_a_hyphen(self):
        # `### Option A: ...` → `option-a-`（docs/adr/template.md で実測）。
        self.assertEqual(check.slugify("Option A: ..."), "option-a-")

    def test_link_in_a_heading_uses_its_text(self):
        self.assertEqual(check.slugify("See [the guide](../guide.md) first"), "see-the-guide-first")


class TestAnchors(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo()
        self.addCleanup(self.repo.cleanup)

    def test_duplicate_headings_get_a_counter(self):
        target = self.repo.write("docs/a.md", "## Notes\n\n## Notes\n\n## Notes\n")
        self.assertEqual(check.anchors_of(target), {"notes", "notes-1", "notes-2"})

    def test_headings_inside_a_fence_are_not_anchors(self):
        target = self.repo.write("docs/a.md", "```bash\n# not a heading\n```\n\n## Real\n")
        self.assertEqual(check.anchors_of(target), {"real"})

    def test_heading_with_inline_code_keeps_its_contents(self):
        # 本文はコードスパンごと落とすが、見出しは中身を残す（docs/processing-migration-guide.md
        # のアンカー 7 本が偽陽性になった実例）。
        target = self.repo.write("docs/a.md", "### `frameRate()` sets, `performance` reads\n")
        self.assertEqual(check.anchors_of(target), {"framerate-sets-performance-reads"})

    def test_html_anchor_is_accepted(self):
        target = self.repo.write("docs/a.md", '<a id="manual"></a>\n\n## Real\n')
        self.assertEqual(check.anchors_of(target), {"manual", "real"})


class TestCheckLinks(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo()
        self.addCleanup(self.repo.cleanup)

    def check(self, *relatives: str) -> list[str]:
        files = [self.repo.root / relative for relative in relatives]
        return check.check_links(self.repo.root, files)

    def test_missing_file_is_reported(self):
        self.repo.write("docs/a.md", "See [b](b.md).\n")
        failures = self.check("docs/a.md")
        self.assertEqual(len(failures), 1, failures)
        self.assertIn("リンク先がありません", failures[0])

    def test_missing_anchor_is_reported(self):
        self.repo.write("docs/b.md", "## Here\n")
        self.repo.write("docs/a.md", "See [b](b.md#there).\n")
        failures = self.check("docs/a.md")
        self.assertEqual(len(failures), 1, failures)
        self.assertIn("見出しがありません", failures[0])

    def test_same_file_anchor_is_checked(self):
        self.repo.write("docs/a.md", "## Here\n\n[up](#there)\n")
        failures = self.check("docs/a.md")
        self.assertEqual(len(failures), 1, failures)
        self.assertIn("見出しがありません", failures[0])

    def test_resolvable_links_pass(self):
        self.repo.write("docs/b.md", "## Here\n")
        self.repo.write("docs/nested/c.md", "[a](../a.md) [dir](../)\n")
        self.repo.write("docs/a.md", "[b](b.md#here) [c](nested/c.md) [ext](https://example.com/x)\n")
        self.assertEqual(self.check("docs/a.md", "docs/nested/c.md"), [])

    def test_links_written_as_code_are_ignored(self):
        # docs/adr/0008 の説明文中の `[こちら](...)` を誤検出しないこと。
        self.repo.write(
            "docs/a.md",
            "同じ URL を `[こちら](...)` のように併記しない。\n\n```markdown\n[x](nope.md)\n```\n",
        )
        self.assertEqual(self.check("docs/a.md"), [])

    def test_percent_encoded_path_is_decoded(self):
        # docs/ai/examples-index.md の `Examples/Topics/Advanced%20Data/...`。
        self.repo.write("Examples/Advanced Data/README.md", "# x\n")
        self.repo.write("docs/a.md", "[x](../Examples/Advanced%20Data/README.md)\n")
        self.assertEqual(self.check("docs/a.md"), [])

    def test_link_outside_the_repository_is_reported(self):
        self.repo.write("docs/a.md", "[out](../../../etc/hosts)\n")
        failures = self.check("docs/a.md")
        self.assertEqual(len(failures), 1, failures)
        self.assertIn("リポジトリの外", failures[0])

    def test_anchor_on_a_non_markdown_target_is_not_checked(self):
        # GitHub の行アンカー（`file.swift#L10`）は見出しではない。
        self.repo.write("Sources/x.swift", "let x = 1\n")
        self.repo.write("docs/a.md", "[x](../Sources/x.swift#L1)\n")
        self.assertEqual(self.check("docs/a.md"), [])

    def test_link_title_and_angle_brackets_are_stripped(self):
        self.repo.write("docs/b.md", "# b\n")
        self.repo.write("docs/a.md", '[t](b.md "title") [u](<b.md>)\n')
        self.assertEqual(self.check("docs/a.md"), [])

    def test_image_links_are_checked_too(self):
        self.repo.write("docs/a.md", "![shot](shot.png)\n")
        failures = self.check("docs/a.md")
        self.assertEqual(len(failures), 1, failures)
        self.assertIn("リンク先がありません", failures[0])


class TestCheckAdrIndex(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo()
        self.addCleanup(self.repo.cleanup)
        self.adr = self.repo.root / "docs" / "adr"

    def write_index(self, *rows: str) -> None:
        body = "# ADR\n\n## 既存 ADR\n\n| # | Status | Title |\n|---|---|---|\n" + "".join(rows)
        self.repo.write("docs/adr/README.md", body)

    def row(self, number: str, name: str) -> str:
        return f"| [{number}]({name}) | Accepted | title |\n"

    def test_consistent_index_passes(self):
        self.repo.write("docs/adr/0001-first.md", "# 1\n")
        self.repo.write("docs/adr/0002-second.md", "# 2\n")
        self.repo.write("docs/adr/template.md", "# template\n")
        self.write_index(self.row("0001", "0001-first.md"), self.row("0002", "0002-second.md"))
        self.assertEqual(check.check_adr_index(self.adr), [])

    def test_adr_missing_from_the_index_is_reported(self):
        self.repo.write("docs/adr/0001-first.md", "# 1\n")
        self.repo.write("docs/adr/0002-second.md", "# 2\n")
        self.write_index(self.row("0001", "0001-first.md"))
        failures = check.check_adr_index(self.adr)
        self.assertEqual(len(failures), 1, failures)
        self.assertIn("索引（docs/adr/README.md）に行がありません", failures[0])

    def test_index_row_without_a_file_is_reported(self):
        self.repo.write("docs/adr/0001-first.md", "# 1\n")
        self.write_index(self.row("0001", "0001-first.md"), self.row("0002", "0002-second.md"))
        failures = check.check_adr_index(self.adr)
        self.assertTrue(any("実ファイルがありません" in failure for failure in failures), failures)

    def test_renamed_file_is_reported(self):
        self.repo.write("docs/adr/0001-renamed.md", "# 1\n")
        self.write_index(self.row("0001", "0001-first.md"))
        failures = check.check_adr_index(self.adr)
        self.assertEqual(len(failures), 1, failures)
        self.assertIn("リンク先が実ファイルと違います", failures[0])

    def test_gap_in_the_numbering_is_reported(self):
        self.repo.write("docs/adr/0001-first.md", "# 1\n")
        self.repo.write("docs/adr/0003-third.md", "# 3\n")
        self.write_index(self.row("0001", "0001-first.md"), self.row("0003", "0003-third.md"))
        failures = check.check_adr_index(self.adr)
        self.assertTrue(any("連番になっていません" in failure for failure in failures), failures)
        self.assertTrue(any("0002" in failure for failure in failures), failures)

    def test_rows_out_of_order_are_reported(self):
        self.repo.write("docs/adr/0001-first.md", "# 1\n")
        self.repo.write("docs/adr/0002-second.md", "# 2\n")
        self.write_index(self.row("0002", "0002-second.md"), self.row("0001", "0001-first.md"))
        failures = check.check_adr_index(self.adr)
        self.assertEqual(len(failures), 1, failures)
        self.assertIn("番号順に並んでいません", failures[0])

    def test_missing_index_is_reported(self):
        self.adr.mkdir(parents=True, exist_ok=True)
        failures = check.check_adr_index(self.adr)
        self.assertEqual(len(failures), 1, failures)
        self.assertIn("ADR 索引がありません", failures[0])


if __name__ == "__main__":
    unittest.main()
