#!/usr/bin/env python3
"""Unit tests for scripts/check-reference-links.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

守りたいのは「Markdown が張る DocC リファレンス URL が 404 になったら落ちる」こと
（Issue #987）。回帰ケースの本命は Issue #959 で実際に死んでいた 2 つの壊れ方で、
どちらも**リンク先の綴りは正しく、シグネチャだけが現行とずれる**:

- 引数ラベルが増えた（`spotlight(…color:)` → `spotlight(…color:intensity:)`）
- DocC の曖昧性解消サフィックスが消えた（`endgifrecord(_:)-57dkf` → `endgifrecord(_:)`）

偽陽性のほうも同じくらい問題になるので、URL の正規化（末尾の `/`・アンカー・
percent-encode・`ja/` 版）と走査対象の線引き（`CHANGELOG.md` は履歴なので対象外、
`changelog.d/` は対象）を固定する。

リポジトリ実体に当てる `TestRepositoryIsConsistent` は `make docs` の出力が要るので、
無いときは skip する（`python3 -m unittest discover` は CI ではビルドの手前で走る）。
"""

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "check-reference-links.py"
_spec = importlib.util.spec_from_file_location("check_reference_links", _SCRIPT)
check = importlib.util.module_from_spec(_spec)
sys.modules["check_reference_links"] = check
_spec.loader.exec_module(check)

REPO_ROOT = Path(__file__).resolve().parents[2]
BASE_URL = "https://shinyaoguri.github.io/metaphor/reference/documentation"


def link(page_path: str) -> str:
    """本文に書かれる形の Markdown リンクを作る。"""
    return f"[symbol]({BASE_URL}/{page_path})"


class TempRepo:
    """テスト用の小さなリポジトリと DocC 出力を作る。"""

    def __init__(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name).resolve()
        self.documentation = self.root / ".build" / "docs" / "data" / "documentation"
        self.documentation.mkdir(parents=True)

    def write(self, relative: str, text: str) -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def page(self, page_path: str) -> Path:
        """DocC が出したページ（`<path>.json`）を 1 枚置く。"""
        path = self.documentation / f"{page_path}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("{}", encoding="utf-8")
        return path

    def check(self, files: list[Path]):
        return check.check_reference_links(self.root, self.documentation, files)

    def cleanup(self) -> None:
        self._tmp.cleanup()


class TestReferencePaths(unittest.TestCase):
    def paths(self, text: str) -> list[str]:
        return [normalized for _, _, normalized in check.reference_paths(text)]

    def test_percent_encoded_parentheses_are_decoded(self):
        self.assertEqual(
            self.paths(link("metaphorcore/sketch/box%28_:%29")),
            ["metaphorcore/sketch/box(_:)"],
        )

    def test_trailing_slash_is_dropped(self):
        self.assertEqual(self.paths(link("metaphorcore/blendmode/")), ["metaphorcore/blendmode"])

    def test_anchor_and_query_are_dropped(self):
        self.assertEqual(
            self.paths(link("metaphorcore/sketch#overview") + link("metaphorcore/param?a=1")),
            ["metaphorcore/sketch", "metaphorcore/param"],
        )

    def test_japanese_reference_shares_the_skeleton(self):
        # ADR-0011: /reference/ja/ は英語版から生成した翻訳で、ページの集合は 1:1。
        text = "[symbol](https://shinyaoguri.github.io/metaphor/reference/ja/documentation/metaphorcore/pi)"
        self.assertEqual(self.paths(text), ["metaphorcore/pi"])

    def test_bare_url_at_the_end_of_a_japanese_sentence(self):
        text = f"詳しくは {BASE_URL}/metaphorcore/pi を参照。"
        self.assertEqual(self.paths(text), ["metaphorcore/pi"])

    def test_documentation_index_has_no_symbol_path(self):
        self.assertEqual(self.paths(link("")), [""])

    def test_placeholder_written_as_inline_code_is_not_a_link(self):
        # 着手当日に DEVELOPMENT.md へ足した説明文がそのまま偽陽性になった実例。
        text = f"本文が張る URL（`{BASE_URL}/…`）は make reference-links-check で検証できます。"
        self.assertEqual(self.paths(text), [])

    def test_url_inside_a_fence_is_not_a_link(self):
        text = f"```\ncurl {BASE_URL}/metaphorcore/gone\n```\n"
        self.assertEqual(self.paths(text), [])

    def test_inline_code_in_the_link_text_does_not_hide_the_link(self):
        # 本文の書き方はほぼ全部これ（[`box(_:)`](URL)）。落とすと検査が丸ごと空になる。
        text = f"- [`box(_:)`]({BASE_URL}/metaphorcore/sketch/box%28_:%29)"
        self.assertEqual(self.paths(text), ["metaphorcore/sketch/box(_:)"])

    def test_line_numbers_are_reported(self):
        text = "\n\n" + link("metaphorcore/pi")
        self.assertEqual([lineno for lineno, _, _ in check.reference_paths(text)], [3])

    def test_the_raw_form_is_kept_for_the_message(self):
        raws = [raw for _, raw, _ in check.reference_paths(link("metaphorcore/sketch/box%28_:%29"))]
        self.assertEqual(raws, ["metaphorcore/sketch/box%28_:%29"])


class TestSymbolKey(unittest.TestCase):
    def test_argument_labels_are_dropped(self):
        self.assertEqual(
            check.symbol_key("metaphorcore/sketch/spotlight(_:_:angle:color:intensity:)"),
            "spotlight",
        )

    def test_disambiguation_suffix_is_dropped(self):
        self.assertEqual(check.symbol_key("metaphorcore/sketch/endgifrecord(_:)-57dkf"), "endgifrecord")

    def test_disambiguation_suffix_on_a_symbol_without_parentheses(self):
        self.assertEqual(check.symbol_key("metaphorcore/sketch/time-4kd9s"), "time")

    def test_underscores_are_not_a_suffix(self):
        self.assertEqual(check.symbol_key("metaphorcore/two_pi"), "two_pi")


class TestCheckReferenceLinks(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo()
        self.addCleanup(self.repo.cleanup)

    def test_existing_page_passes(self):
        self.repo.page("metaphorcore/sketch/box(_:)")
        source = self.repo.write("docs/a.md", link("metaphorcore/sketch/box%28_:%29"))
        failures, seen = self.repo.check([source])
        self.assertEqual(failures, [])
        self.assertEqual(seen, 1)

    def test_added_argument_label_is_caught_with_the_replacement(self):
        # Issue #959 の 1〜3 本目。ライトに `intensity:` が増えて本文が取り残された。
        self.repo.page("metaphorcore/sketch/spotlight(_:_:angle:color:intensity:)")
        source = self.repo.write("docs/a.md", link("metaphorcore/sketch/spotlight%28_:_:angle:color:%29"))
        failures, _ = self.repo.check([source])
        self.assertEqual(len(failures), 1)
        self.assertIn("docs/a.md:1", failures[0])
        self.assertIn("spotlight(_:_:angle:color:intensity:)", failures[0])

    def test_removed_disambiguation_suffix_is_caught_with_the_replacement(self):
        # Issue #959 の 4 本目。別名化で同名シンボルが 1 つになり `-57dkf` が消えた。
        self.repo.page("metaphorcore/sketch/endgifrecord(_:)")
        source = self.repo.write("docs/a.md", link("metaphorcore/sketch/endgifrecord%28_:%29-57dkf"))
        failures, _ = self.repo.check([source])
        self.assertEqual(len(failures), 1)
        self.assertIn("metaphorcore/sketch/endgifrecord(_:)", failures[0])

    def test_moved_symbol_is_found_outside_its_parent(self):
        # 型ごと移った場合は親ディレクトリに候補が無いので、全体から同名の葉を探す。
        self.repo.page("metaphorcore/canvas3d/lights()")
        source = self.repo.write("docs/a.md", link("metaphorcore/sketch/lights%28%29"))
        failures, _ = self.repo.check([source])
        self.assertIn("metaphorcore/canvas3d/lights()", failures[0])

    def test_missing_page_without_a_candidate_reports_no_suggestion(self):
        source = self.repo.write("docs/a.md", link("metaphorcore/gone"))
        failures, _ = self.repo.check([source])
        self.assertEqual(len(failures), 1)
        self.assertNotIn("候補", failures[0])

    def test_documentation_index_is_not_checked(self):
        source = self.repo.write("docs/a.md", link(""))
        failures, seen = self.repo.check([source])
        self.assertEqual(failures, [])
        self.assertEqual(seen, 1)


class TestMarkdownFiles(unittest.TestCase):
    def setUp(self):
        self.repo = TempRepo()
        self.addCleanup(self.repo.cleanup)

    def files(self) -> set[str]:
        return {
            path.relative_to(self.repo.root).as_posix()
            for path in check.markdown_files(self.repo.root)
        }

    def test_scanned_surfaces(self):
        self.repo.write("docs/tutorial/05-3d.md", "")
        self.repo.write("Examples/LEARNING_PATH.md", "")
        self.repo.write("Sources/metaphor/metaphor.docc/MetaphorCore.md", "")
        self.repo.write("changelog.d/533.removed.md", "")
        self.repo.write("website/README.md", "")
        self.repo.write("README.md", "")
        self.assertEqual(
            self.files(),
            {
                "docs/tutorial/05-3d.md",
                "Examples/LEARNING_PATH.md",
                "Sources/metaphor/metaphor.docc/MetaphorCore.md",
                "changelog.d/533.removed.md",
                "website/README.md",
                "README.md",
            },
        )

    def test_changelog_is_out_of_scope(self):
        # リリース時点の記述を保存する履歴。当時のリファレンスの姿を指している。
        self.repo.write("CHANGELOG.md", link("metaphorcore/gone"))
        self.assertEqual(self.files(), set())

    def test_build_output_is_out_of_scope(self):
        # .build には DocC 出力そのものと依存パッケージの Markdown が入る。
        self.repo.write(".build/checkouts/other/README.md", "")
        self.repo.write("website/node_modules/pkg/README.md", "")
        self.assertEqual(self.files(), set())


class TestRepositoryIsConsistent(unittest.TestCase):
    """リポジトリ実体の全リンクが `make docs` の出力に当たることを確かめる。

    DocC 出力はビルド生成物なので、無いときは skip する。CI では
    `make reference-links-check` が同じ判定を生成込みで走らせる。
    """

    def test_all_reference_links_resolve(self):
        documentation = REPO_ROOT / ".build" / "docs" / "data" / "documentation"
        if not documentation.is_dir():
            self.skipTest("DocC の出力がありません（`make docs` で生成できます）")
        files = check.markdown_files(REPO_ROOT)
        failures, seen = check.check_reference_links(REPO_ROOT, documentation, files)
        self.assertEqual(failures, [], "\n".join(failures))
        self.assertGreater(seen, 0, "リファレンスへのリンクが 1 本も見つかりません（走査対象がずれた？）")


if __name__ == "__main__":
    unittest.main()
