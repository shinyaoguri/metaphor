#!/usr/bin/env python3
"""Unit tests for scripts/generate-tutorial-status.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

「チュートリアルがどこまで公開されているか」の正典は docs/tutorial/*.md の
frontmatter で、README 群の案内はその生成物（Issue #584）。ここでは擬似的な
リポジトリを tmpdir に組み立て、文面の出し分け・陳腐化検出・整合チェックの
規則を固定する。
"""

import contextlib
import importlib.util
import io
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "generate-tutorial-status.py"
_spec = importlib.util.spec_from_file_location("generate_tutorial_status", _SCRIPT)
gen = importlib.util.module_from_spec(_spec)
sys.modules["generate_tutorial_status"] = gen
_spec.loader.exec_module(gen)

# 章立て表（docs/tutorial/README.md）と部の表（README.md）の最小形。テストごとに
# 中身を組み替えるので、行の組み立てはヘルパへ寄せる。
OUTLINE_HEADER = "| 部 | ファイル | 状態 |\n|---|---|---|\n"


class StatusTestCase(unittest.TestCase):
    """tmpdir に docs/tutorial と入口ドキュメントを持つ疑似リポを張る。"""

    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.tutorial = self.root / "docs/tutorial"
        self.tutorial.mkdir(parents=True)
        for name, value in (("REPO_ROOT", self.root), ("TUTORIAL_DIR", self.tutorial)):
            original = getattr(gen, name)
            setattr(gen, name, value)
            self.addCleanup(setattr, gen, name, original)
        # 既定では入口ドキュメントを 1 枚だけ登録する（テストごとに差し替え可）。
        self.set_docs(("README.md",))
        self.parts: list[tuple[int, str, str, bool]] = []

    def set_docs(self, status_docs, link_docs=("README.md",)) -> None:
        for name, value in (("STATUS_DOCS", status_docs), ("LINK_DOCS", link_docs)):
            original = getattr(gen, name)
            setattr(gen, name, value)
            self.addCleanup(setattr, gen, name, original)

    def add_part(self, number: int, title: str, slug: str, draft: bool = False) -> str:
        """本文 1 部を置き、そのファイル名を返す。"""
        filename = f"{number:02d}-{slug}.md"
        draft_line = f"draft: {'true' if draft else 'false'}\n"
        (self.tutorial / filename).write_text(
            f"---\ntitle: {title}\npart: {number}\nslug: {slug}\n{draft_line}---\n\n"
            f"# 第 {number} 部 {title}\n",
            encoding="utf-8",
        )
        self.parts.append((number, title, filename, draft))
        return filename

    def write_doc(self, rel: str, text: str) -> Path:
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def write_outline(self, states: dict[int, str] | None = None) -> None:
        """章立て表を書く。states で状態欄だけ上書きできる（ずれの再現用）。"""
        states = states or {}
        rows = "".join(
            f"| 第 {number} 部 {title} | [`{filename}`]({filename}) | "
            f"{states.get(number, '執筆中' if draft else '公開')} |\n"
            for number, title, filename, draft in self.parts
        )
        self.write_doc("docs/tutorial/README.md", OUTLINE_HEADER + rows)

    def write_link_doc(self, rel: str = "README.md", skip: set[int] = frozenset()) -> None:
        """部の表を持つ入口ドキュメント。執筆中の部と skip の部へは張らない。"""
        rows = "".join(
            f"| [第 {number} 部 {title}](docs/tutorial/{filename}) | 学べること |\n"
            for number, title, filename, draft in self.parts
            if not draft and number not in skip
        )
        self.write_doc(
            rel,
            "## チュートリアル\n\n"
            + rows
            + "\n<!-- tutorial-status: ja-status --><!-- /tutorial-status -->です。\n",
        )

    def run_main(self, *argv: str) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        original = sys.argv
        sys.argv = ["generate-tutorial-status.py", *argv]
        try:
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = gen.main()
        finally:
            sys.argv = original
        return code, out.getvalue(), err.getvalue()

    def add_parts(self, published: int, drafts: int = 0) -> None:
        """第 1 部から published 本を公開、続く drafts 本を執筆中で置く。"""
        for number in range(1, published + drafts + 1):
            self.add_part(number, f"タイトル{number}", f"slug{number}", number > published)


class TestStatusPhrases(StatusTestCase):
    """公開状況の文面。website も README も同じ 1 句を共有する。"""

    def phrases(self) -> tuple[str, str]:
        parts = gen.tutorial_parts()
        return gen.ja_status(parts), gen.en_status(parts)

    def test_all_published(self) -> None:
        self.add_parts(published=10)
        self.assertEqual(
            self.phrases(), ("第 1 部〜第 10 部を公開中", "Parts 1–10 are published")
        )

    def test_published_prefix_with_trailing_drafts(self) -> None:
        self.add_parts(published=5, drafts=5)
        self.assertEqual(
            self.phrases(),
            (
                "第 1 部〜第 5 部を公開中。第 6 部以降は執筆中",
                "Parts 1–5 are published, Part 6 onward is being written",
            ),
        )

    def test_single_published_part_is_not_a_range(self) -> None:
        self.add_parts(published=1, drafts=1)
        self.assertEqual(
            self.phrases(),
            (
                "第 1 部を公開中。第 2 部以降は執筆中",
                "Part 1 is published, Part 2 onward is being written",
            ),
        )

    def test_gap_is_listed_instead_of_a_range(self) -> None:
        # 第 2 部だけ執筆中に戻る場合、「第 1 部〜第 3 部」と言ってはいけない。
        self.add_part(1, "一", "one")
        self.add_part(2, "二", "two", draft=True)
        self.add_part(3, "三", "three")
        self.assertEqual(
            self.phrases(),
            (
                "第 1・3 部を公開中。第 2 部は執筆中",
                "Parts 1, 3 are published, Part 2 is being written",
            ),
        )

    def test_nothing_published(self) -> None:
        self.add_parts(published=0, drafts=2)
        self.assertEqual(
            self.phrases(), ("まだ公開されていません", "No parts are published yet")
        )

    def test_links_skip_drafts_and_take_a_prefix(self) -> None:
        self.add_parts(published=2, drafts=1)
        self.assertEqual(
            gen.ja_links(gen.tutorial_parts(), "tutorial/"),
            "[第 1 部 タイトル1](tutorial/01-slug1.md) / "
            "[第 2 部 タイトル2](tutorial/02-slug2.md)",
        )

    def test_part_number_falls_back_to_the_filename(self) -> None:
        # part: は website 側でも省略可（ファイル名の数字から補う）。
        (self.tutorial / "07-media.md").write_text(
            "---\ntitle: メディア\nslug: media\n---\n", encoding="utf-8"
        )
        self.assertEqual([p.number for p in gen.tutorial_parts()], [7])


class TestGeneration(StatusTestCase):
    """マーカーの書き換えと陳腐化検出。"""

    def setUp(self) -> None:
        super().setUp()
        self.add_parts(published=2)
        self.write_outline()

    def test_fills_every_marker_kind(self) -> None:
        self.set_docs(("README.md", "docs/README.md"))
        self.write_link_doc()
        doc = self.write_doc(
            "docs/README.md",
            "| 入門者 | [tutorial/](tutorial/)"
            "（<!-- tutorial-status: ja-status --><!-- /tutorial-status -->） |\n"
            "- 公開中の本文: <!-- tutorial-status: ja-links:tutorial/ -->"
            "<!-- /tutorial-status -->。\n"
            "EN: <!-- tutorial-status: en-status --><!-- /tutorial-status -->\n",
        )

        self.assertEqual(self.run_main()[0], 0)
        text = doc.read_text(encoding="utf-8")
        self.assertIn(
            "（<!-- tutorial-status: ja-status -->第 1 部〜第 2 部を公開中"
            "<!-- /tutorial-status -->）",
            text,
        )
        self.assertIn("[第 1 部 タイトル1](tutorial/01-slug1.md)", text)
        self.assertIn("EN: <!-- tutorial-status: en-status -->Parts 1–2 are published", text)
        # 表のセルに入れられるよう、マーカーは行を分けない。
        self.assertEqual(len(text.rstrip("\n").split("\n")), 3)

    def test_regeneration_is_idempotent(self) -> None:
        self.write_link_doc()
        self.assertEqual(self.run_main()[0], 0)
        first = (self.root / "README.md").read_text(encoding="utf-8")
        self.assertEqual(self.run_main()[0], 0)
        self.assertEqual(first, (self.root / "README.md").read_text(encoding="utf-8"))

    def test_check_reports_stale_text_with_a_diff(self) -> None:
        self.write_doc(
            "README.md",
            "| [第 1 部 タイトル1](docs/tutorial/01-slug1.md) |\n"
            "| [第 2 部 タイトル2](docs/tutorial/02-slug2.md) |\n"
            "<!-- tutorial-status: ja-status -->第 1 部のみ公開中<!-- /tutorial-status -->\n",
        )

        code, out, err = self.run_main("--check")
        self.assertEqual(code, 1)
        self.assertIn("-<!-- tutorial-status: ja-status -->第 1 部のみ公開中", out)
        self.assertIn("+<!-- tutorial-status: ja-status -->第 1 部〜第 2 部を公開中", out)
        self.assertIn("公開状況の案内が古い", err)
        # --check は書き換えない。
        self.assertIn("第 1 部のみ公開中", (self.root / "README.md").read_text())

    def test_unknown_marker_kind_is_an_error(self) -> None:
        self.write_doc(
            "README.md",
            "<!-- tutorial-status: ja-summary --><!-- /tutorial-status -->\n",
        )
        code, _, err = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("知らない tutorial-status の種類", err)

    def test_unopened_close_marker_is_an_error(self) -> None:
        self.write_doc("README.md", "本文<!-- /tutorial-status -->\n")
        code, _, err = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("開始マーカーの無い", err)


class TestConsistencyChecks(StatusTestCase):
    """生成物に落とせない整合（導線の有無・章立て表の状態欄）。"""

    def setUp(self) -> None:
        super().setUp()
        self.add_parts(published=2, drafts=1)

    def test_all_green_when_links_and_outline_agree(self) -> None:
        self.write_link_doc()
        self.write_outline()
        self.assertEqual(self.run_main()[0], 0)

    def test_missing_link_to_a_published_part_fails(self) -> None:
        self.write_link_doc(skip={2})
        self.write_outline()
        code, _, err = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("公開済みの第 2 部への導線が無い", err)

    def test_link_to_a_draft_part_fails(self) -> None:
        # 執筆中の第 3 部へ張ってしまった README（先走った導線を捕まえる）。
        self.write_link_doc()
        path = self.root / "README.md"
        path.write_text(
            path.read_text(encoding="utf-8")
            + "| [第 3 部 タイトル3](docs/tutorial/03-slug3.md) |\n",
            encoding="utf-8",
        )
        self.write_outline()
        code, _, err = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("執筆中の第 3 部へ導線が張られている", err)

    def test_outline_state_out_of_sync_fails(self) -> None:
        self.write_link_doc()
        self.write_outline(states={3: "公開"})  # frontmatter は draft: true
        code, _, err = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("第 3 部の状態が '公開' だが frontmatter では '執筆中'", err)

    def test_part_missing_from_the_outline_fails(self) -> None:
        self.write_link_doc()
        self.parts = [p for p in self.parts if p[0] != 2]
        self.write_outline()
        code, _, err = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("第 2 部が章立て表に無い", err)


class TestFrontmatterErrors(StatusTestCase):
    def test_missing_frontmatter_is_an_error(self) -> None:
        (self.tutorial / "01-x.md").write_text("# 見出しだけ\n", encoding="utf-8")
        code, _, err = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("frontmatter が無い", err)

    def test_duplicate_part_numbers_are_an_error(self) -> None:
        self.add_part(1, "一", "one")
        self.add_part(1, "壱", "uno")
        code, _, err = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("部番号が重複している", err)


if __name__ == "__main__":
    unittest.main()
