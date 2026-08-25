#!/usr/bin/env python3
"""Unit tests for scripts/changelog.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

守りたいのは「`changelog.d/` のエントリが相対リンクを持っていたら落ちる」こと
（Issue #1181）。理由は 1 行で言える — **エントリの本文はエントリファイルの隣では
読まれない**。`collect` はルートの `CHANGELOG.md` へ、`notes` は GitHub Release の
body へ、同じ文字列を差し込む。どちらも `changelog.d/` を基点にしないので、相対
リンクは畳み込まれた瞬間に切れる。**Release body は後から直せない**ので、書いた
本人の PR で止めるしかない。

回帰ケースの本命は #1151 が実際に見つけた壊れ方で、`CHANGELOG.md` に 12 本残って
いた（PR #1182 で絶対 URL へ張り替え済み）:

    404  https://github.com/shinyaoguri/metaphor/blob/docs/tutorial/
    200  https://github.com/shinyaoguri/metaphor/blob/main/docs/tutorial/

偽陽性のほうも同じくらい問題になるので、線引きも固定する: コードスパン・フェンス内
は対象外（`check-docs-links.py` / `check-reference-links.py` と同じ `strip_code` の
作法）、`changelog.d/README.md` は畳み込まれないエントリ以外のファイルなので対象外
（実際に `../CHANGELOG.md` などを正しく張っている）。
"""

import contextlib
import importlib.util
import io
import sys
import tempfile
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "changelog.py"
_spec = importlib.util.spec_from_file_location("changelog", _SCRIPT)
changelog = importlib.util.module_from_spec(_spec)
sys.modules["changelog"] = changelog
_spec.loader.exec_module(changelog)

REPO_ROOT = Path(__file__).resolve().parents[2]

# 畳み込み先の `## [Unreleased]` があるだけの最小の CHANGELOG.md。`check` にも
# 通せるよう link definition まで持たせる。
MINIMAL_CHANGELOG = """# Changelog

## [Unreleased]

[Unreleased]: https://github.com/shinyaoguri/metaphor/compare/v0.1.0...HEAD
"""


class EntryDir:
    """`changelog.d/` に見立てた一時ディレクトリ。"""

    def __init__(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name).resolve()
        self.dir = self.root / "changelog.d"
        self.dir.mkdir()
        self.changelog = self.root / "CHANGELOG.md"
        self.changelog.write_text(MINIMAL_CHANGELOG, encoding="utf-8")

    def write(self, name: str, text: str) -> Path:
        path = self.dir / name
        path.write_text(text, encoding="utf-8")
        return path

    def lint(self) -> tuple[int, str]:
        """`changelog.py lint` を走らせて (exit code, stderr) を返す。"""
        return self._run("lint")

    def check(self) -> tuple[int, str]:
        return self._run("check")

    def _run(self, command: str) -> tuple[int, str]:
        err = io.StringIO()
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(err):
            code = changelog.main(
                ["--path", str(self.changelog), "--dir", str(self.dir), command]
            )
        return code, err.getvalue()

    def __enter__(self) -> "EntryDir":
        return self

    def __exit__(self, *exc) -> None:
        self._tmp.cleanup()


class TestRelativeLinks(unittest.TestCase):
    """`relative_links()` が拾うもの・拾わないもの。"""

    def targets(self, text: str) -> list[str]:
        return [target for _, target in changelog.relative_links(text)]

    def test_absolute_urls_are_fine(self):
        self.assertEqual(
            self.targets(
                "- Fixed ([#382](https://github.com/shinyaoguri/metaphor/issues/382)),\n"
                "  see [the guide](http://example.com/a) or [mail](mailto:x@example.com).\n"
            ),
            [],
        )

    def test_angle_bracketed_absolute_url_is_fine(self):
        # `](<https://…>)` は絶対 URL の正当な書き方。山カッコごと判定すると偽陽性。
        self.assertEqual(self.targets("- [x](<https://example.com/a(b)>)\n"), [])

    def test_parent_relative_link_is_caught(self):
        # #1151 が実際に見つけた壊れ方。`../docs/tutorial/` は畳み込み先の
        # CHANGELOG.md から見るとリポジトリの外を指す。
        self.assertEqual(
            self.targets("- Tutorials live in [`docs/tutorial/`](../docs/tutorial/).\n"),
            ["../docs/tutorial/"],
        )

    def test_other_relative_shapes_are_caught(self):
        self.assertEqual(
            self.targets("- [a](./a.md) [b](docs/b.md) [c](/docs/c.md)\n"),
            ["./a.md", "docs/b.md", "/docs/c.md"],
        )

    def test_same_file_anchor_is_caught(self):
        # #1010 の CONTRACT.md はそれ自体が 1 つの文書として描画されるのでアンカーが
        # 効くが、エントリファイルは一度も描画されない。`#fixed` は CHANGELOG.md では
        # 何十個もある `### Fixed` の先頭へ、Release body ではその時々の見出しへ着地
        # する ＝ 404 にならず黙って別の場所へ飛ぶ。
        self.assertEqual(self.targets("- See [below](#fixed).\n"), ["#fixed"])

    def test_relative_image_is_caught(self):
        # 画像もリンクと同じ。そもそも画像は Gyazo の絶対 URL が規約（ADR-0008）。
        self.assertEqual(
            self.targets("- New look: ![shot](../docs/img/x.png)\n"), ["../docs/img/x.png"]
        )

    def test_inline_code_is_not_a_link(self):
        # パスを**説明する**エントリを「リンクが相対だ」と誤検出しない。
        self.assertEqual(
            self.targets("- `loadImage()` no longer resolves `[data](../data/x.png)`.\n"), []
        )

    def test_fenced_block_is_not_a_link(self):
        self.assertEqual(
            self.targets("- Before:\n\n  ```markdown\n  [old](../docs/x.md)\n  ```\n"), []
        )

    def test_line_numbers_are_reported(self):
        # フェンスは空行に置き換えるので、その後ろの行番号がずれない。
        text = "- one\n\n  ```swift\n  let x = 1\n  ```\n\n- [two](../b.md)\n"
        self.assertEqual(changelog.relative_links(text), [(7, "../b.md")])


class TestLint(unittest.TestCase):
    """`changelog.py lint` / `check` が実際に落ちるか。"""

    def test_relative_link_fails_lint(self):
        with EntryDir() as entries:
            entries.write(
                "1151.fixed.md",
                "- Tutorials live in [`docs/tutorial/`](../docs/tutorial/).\n",
            )
            code, err = entries.lint()
        self.assertEqual(code, 1)
        self.assertIn("1151.fixed.md:1", err)
        self.assertIn("../docs/tutorial/", err)

    def test_error_message_gives_the_reason(self):
        """次に書く人がその場で理解できるだけの理由が出ているか（#1181）。"""
        with EntryDir() as entries:
            entries.write("x.fixed.md", "- [a](../a.md)\n")
            _, err = entries.lint()
        self.assertIn("absolute URL", err)
        self.assertIn("never rendered next to its own file", err)
        self.assertIn("GitHub Release body", err)
        self.assertIn("cannot be corrected once the release is cut", err)
        # 直し方（ファイルは blob/main、ディレクトリは tree/main）も出す。
        self.assertIn("/blob/main/", err)
        self.assertIn("/tree/main/", err)

    def test_absolute_url_passes_lint(self):
        with EntryDir() as entries:
            entries.write(
                "1151.fixed.md",
                "- Tutorials live in [`docs/tutorial/`]"
                "(https://github.com/shinyaoguri/metaphor/tree/main/docs/tutorial/).\n",
            )
            code, err = entries.lint()
        self.assertEqual(code, 0, err)

    def test_code_span_passes_lint(self):
        with EntryDir() as entries:
            entries.write("x.fixed.md", "- Paths like `[a](../a.md)` are prose, not links.\n")
            code, err = entries.lint()
        self.assertEqual(code, 0, err)

    def test_readme_is_not_an_entry(self):
        """`changelog.d/README.md` は畳み込まれないので相対リンクのままで正しい。"""
        with EntryDir() as entries:
            entries.write("README.md", "See [CHANGELOG.md](../CHANGELOG.md).\n")
            code, err = entries.lint()
        self.assertEqual(code, 0, err)

    def test_release_time_check_also_fails(self):
        """毎 PR の網を抜けたエントリも、リリースの入口で止まる。"""
        with EntryDir() as entries:
            entries.write("x.fixed.md", "- [a](../a.md)\n")
            code, err = entries.lint()
            self.assertEqual(code, 1)
            code, err = entries.check()
        self.assertEqual(code, 1)
        self.assertIn("../a.md", err)


class TestRepositoryIsClean(unittest.TestCase):
    """規則を入れた時点の `changelog.d/` が違反 0 件であること。

    新しい規則が既存の借金を作っていないことの確認であり、以後は「エントリを足す
    PR がその場で捕まる」ことの確認でもある。
    """

    def test_no_relative_links_in_changelog_d(self):
        offenders = []
        for path in sorted((REPO_ROOT / "changelog.d").glob("*.md")):
            if path.name in changelog.NOT_AN_ENTRY:
                continue
            for lineno, target in changelog.relative_links(path.read_text(encoding="utf-8")):
                offenders.append(f"{path.name}:{lineno}: {target}")
        self.assertEqual(offenders, [])


if __name__ == "__main__":
    unittest.main()
