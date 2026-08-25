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

もう半分は参照形式（Issue #1184）。リンク先が絶対 URL なので #1181 の検査は通るのに、
**別の壊れ方で同じ結末**になる:

    - Tutorials now ship as sketches ([#511][issue]).

    [issue]: https://github.com/shinyaoguri/metaphor/issues/511

定義行は `collect` に `## [Unreleased]` の**中へ**畳み込まれ、そこで定義であることを
やめる。`notes` は `LINK_DEF_RE` に当たる行を節から落とすので Release body には
`[#511][issue]` が字面のまま残り、**次のリリースの `collect` はその定義行を跨げず
exit 1 で止まる**。定義を `CHANGELOG.md` の末尾ブロックへ置き直しても、`notes` は
節を 1 つコピーするだけなので Release body には届かない ＝ **定義の置き場は存在しない**。
だから定義行だけでなく参照形式リンクそのものを弾く（定義行だけ弾くと、素直に定義を
消した結果 `[#511][issue]` が字面のまま lint を通ってしまう）。

`## [Unreleased]` の中の定義行を見るガードは元から `collect()` にあったが、そこは
リリースジョブの**中**で、入口ゲート（`check`）を通り過ぎた後。`lint` / `check` へ
前倒しして、書いた本人の PR で止める。
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

# 畳み込み先の `## [Unreleased]` を持つ最小の CHANGELOG.md。
#
# 版のセクションを 1 つ挟むのは飾りではない。link definition ブロックは常に
# ファイル末尾に置かれ、`parse()` は最後の `## [...]` の body をファイル末まで
# 取るので、`## [Unreleased]` を唯一のセクションにすると**ブロックが Unreleased
# の中に入る**。その形は `collect` が昔から拒む（実測: origin/main の
# `changelog.py collect` も exit 1）ので、テストの土台としては実物と違う。
# 実物の CHANGELOG.md は Unreleased + 21 版 + 末尾ブロックで、末尾ブロックは
# 最後の版のセクション側にある。
MINIMAL_CHANGELOG = """# Changelog

## [Unreleased]

## [0.1.0] - 2026-01-01

### Added

- First release.

[Unreleased]: https://github.com/shinyaoguri/metaphor/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/shinyaoguri/metaphor/releases/tag/v0.1.0
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

    def write_changelog(self, text: str) -> None:
        self.changelog.write_text(text, encoding="utf-8")

    def lint(self) -> tuple[int, str]:
        """`changelog.py lint` を走らせて (exit code, stderr) を返す。"""
        return self._run("lint")

    def check(self) -> tuple[int, str]:
        return self._run("check")

    def collect(self) -> tuple[int, str]:
        return self._run("collect")

    def notes(self, section: str = "unreleased") -> str:
        """`changelog.py notes` の stdout（Release body に入る文字列そのもの）。"""
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            changelog.main(
                ["--path", str(self.changelog), "--dir", str(self.dir), "notes", section]
            )
        return out.getvalue()

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


class TestReferenceLinks(unittest.TestCase):
    """`reference_links()` が拾うもの・拾わないもの（Issue #1184）。"""

    def found(self, text: str) -> list[str]:
        return [link for _, link in changelog.reference_links(text)]

    def test_full_reference_is_caught(self):
        # Issue #1184 の再現ケースそのもの。
        self.assertEqual(
            self.found("- Tutorials now ship as sketches ([#511][issue]).\n"),
            ["[#511][issue]"],
        )

    def test_collapsed_reference_is_caught(self):
        # `[text][]` は定義の id を text から取る書き方。壊れ方は full と同じ。
        self.assertEqual(self.found("- See [#511][].\n"), ["[#511][]"])

    def test_reference_image_is_caught(self):
        self.assertEqual(self.found("- New look: ![shot][img]\n"), ["![shot][img]"])

    def test_inline_link_is_not_a_reference(self):
        # #1181 が通す正しい書き方を、こちらが弾き返さないこと。
        self.assertEqual(
            self.found("- Fixed ([#382](https://github.com/shinyaoguri/metaphor/issues/382)).\n"),
            [],
        )

    def test_shortcut_reference_is_deliberately_not_caught(self):
        """裸の `[text]` は追わない — 普通の角カッコと区別できないため。

        追わなくても穴にならない: 裸の参照を*リンクとして*成立させるには
        `[text]: <url>` の定義行が要り、それは `link_definitions()` が捕まえる。
        定義の無い `[text]` は字面が残るだけで、リリースは止まらない。
        """
        self.assertEqual(self.found("- Marked [experimental] in the docs.\n"), [])

    def test_code_span_is_not_a_reference(self):
        # 参照記法を**説明する**エントリを弾かない。
        self.assertEqual(self.found("- Write `[#511][issue]` inline instead.\n"), [])

    def test_fenced_block_is_not_a_reference(self):
        self.assertEqual(self.found("- Before:\n\n  ```markdown\n  [a][b]\n  ```\n"), [])

    def test_line_numbers_are_reported(self):
        self.assertEqual(
            changelog.reference_links("- one\n\n- see [two][ref]\n"), [(3, "[two][ref]")]
        )


class TestLinkDefinitions(unittest.TestCase):
    """`link_definitions()` の線引き。

    こちらだけは `strip_code()` を通さない。守る相手（`body_lines()` と
    `collect()` のガード）が同じ行正規表現をフェンス無視で当てているので、
    検査を賢くすると壊れ方より狭くなる。
    """

    def found(self, text: str) -> list[str]:
        return [line for _, line in changelog.link_definitions(text)]

    def test_definition_line_is_caught(self):
        self.assertEqual(
            self.found("- Fixed ([#511][issue]).\n\n[issue]: https://example.com/511\n"),
            ["[issue]: https://example.com/511"],
        )

    def test_definition_inside_a_fence_is_caught_too(self):
        """フェンスの中でも桁 0 なら拾う。実際に壊れるのはこの位置だから
        （壊れることは test_body_lines_guts_a_fenced_definition が実測する）。"""
        self.assertEqual(
            self.found("- Was:\n\n```markdown\n[issue]: https://example.com/511\n```\n"),
            ["[issue]: https://example.com/511"],
        )

    def test_indented_definition_is_not_caught(self):
        # `LINK_DEF_RE` は桁 0 固定。インデントされた行は畳み込み後も定義では
        # ないので `body_lines()` も落とさない ＝ 弾く理由がない。
        self.assertEqual(self.found("- Was:\n\n  [issue]: https://example.com/511\n"), [])

    def test_ordinary_prose_is_not_a_definition(self):
        self.assertEqual(self.found("- The [Unreleased]: section moved.\n"), [])

    def test_body_lines_guts_a_fenced_definition(self):
        """「桁 0 ならフェンス内でも壊れる」ことの実測。

        `body_lines()` は行単位でフェンスを知らないので、フェンスの中身だけが
        抜き取られて Release body に空のコードブロックが残る。
        """
        lines = (
            "# Changelog\n\n## [Unreleased]\n\n- Was:\n\n"
            "```markdown\n[issue]: https://example.com/511\n```\n"
        ).split("\n")
        section = changelog.find(changelog.parse(lines), "Unreleased")
        body = "\n".join(changelog.body_lines(lines, section))
        self.assertIn("```markdown\n```", body)
        self.assertNotIn("https://example.com/511", body)


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


class TestReferenceStyleLint(unittest.TestCase):
    """Issue #1184 の再現ケースが、書いた本人の PR で止まるか。"""

    ENTRY = (
        "- Tutorials now ship as sketches ([#511][issue]).\n"
        "\n"
        "[issue]: https://github.com/shinyaoguri/metaphor/issues/511\n"
    )

    def test_issue_1184_reproduction_fails_lint(self):
        with EntryDir() as entries:
            entries.write("1184.fixed.md", self.ENTRY)
            code, err = entries.lint()
        self.assertEqual(code, 1)
        # 参照側と定義側、両方の行番号を挙げる（片方だけ直しても通らない）。
        self.assertIn("1184.fixed.md:1", err)
        self.assertIn("[#511][issue]", err)
        self.assertIn("1184.fixed.md:3", err)
        self.assertIn("[issue]: https://github.com/shinyaoguri/metaphor/issues/511", err)

    def test_release_time_check_also_fails(self):
        """毎 PR の網を抜けても、リリースの入口ゲートで止まる。"""
        with EntryDir() as entries:
            entries.write("1184.fixed.md", self.ENTRY)
            code, err = entries.check()
        self.assertEqual(code, 1)
        self.assertIn("[#511][issue]", err)

    def test_deleting_only_the_definition_still_fails(self):
        """定義行だけ消すのは直っていない — そこで通したら検査が誘導した罠になる。

        定義の無い `[#511][issue]` は `CHANGELOG.md` でも Release body でも
        字面のまま残る。参照側も弾いている理由がこれ。
        """
        with EntryDir() as entries:
            entries.write("1184.fixed.md", "- Tutorials now ship as sketches ([#511][issue]).\n")
            code, err = entries.lint()
        self.assertEqual(code, 1)
        self.assertIn("[#511][issue]", err)

    def test_error_message_gives_the_reason_and_the_fix(self):
        with EntryDir() as entries:
            entries.write("1184.fixed.md", self.ENTRY)
            _, err = entries.lint()
        # なぜダメか: 2 つの描画先それぞれで壊れること。
        self.assertIn("nowhere to keep", err)
        self.assertIn("Release body cannot be corrected once the release is cut", err)
        self.assertIn("next* release's `collect` refuses to run", err)
        self.assertIn("copies one section rather than the", err)
        # どう直すか。
        self.assertIn("Write the link inline", err)
        self.assertIn("code span", err)

    def test_inline_rewrite_passes(self):
        """error message が指示する直し方が、実際に通ること。"""
        with EntryDir() as entries:
            entries.write(
                "1184.fixed.md",
                "- Tutorials now ship as sketches "
                "([#511](https://github.com/shinyaoguri/metaphor/issues/511)).\n",
            )
            code, err = entries.lint()
        self.assertEqual(code, 0, err)

    def test_code_span_passes_lint(self):
        """参照記法を説明するだけのエントリを弾かない（偽陽性側）。"""
        with EntryDir() as entries:
            entries.write(
                "1184.changed.md",
                "- Entries must not use `[text][id]`; write links inline.\n",
            )
            code, err = entries.lint()
        self.assertEqual(code, 0, err)

    def test_both_link_problems_are_reported_together(self):
        """相対リンクと参照形式が同居しても、片方が隠れない。"""
        with EntryDir() as entries:
            entries.write("x.fixed.md", "- [a](../a.md) and [b][ref]\n")
            code, err = entries.lint()
        self.assertEqual(code, 1)
        self.assertIn("../a.md", err)
        self.assertIn("[b][ref]", err)


class TestLinkDefsInUnreleased(unittest.TestCase):
    """`## [Unreleased]` の中の定義行を、リリースの入口より手前で止める。

    このガードは元から `collect()` にあったが、`collect` はリリースジョブの
    **中**（examples のスモークビルドを挟んだ後）で走る。エントリファイルを
    経由せず `## [Unreleased]` へ直接書く逃げ道は changelog.d/README.md が
    正規の手順として案内しているので、`validate()` だけでは塞がらない。
    """

    DIRTY = (
        "# Changelog\n"
        "\n"
        "## [Unreleased]\n"
        "\n"
        "### Fixed\n"
        "\n"
        "- Tutorials now ship as sketches ([#511][issue]).\n"
        "\n"
        "[issue]: https://github.com/shinyaoguri/metaphor/issues/511\n"
        "\n"
        "## [0.1.0] - 2026-01-01\n"
        "\n"
        "### Added\n"
        "\n"
        "- First release.\n"
        "\n"
        "[Unreleased]: https://github.com/shinyaoguri/metaphor/compare/v0.1.0...HEAD\n"
        "[0.1.0]: https://github.com/shinyaoguri/metaphor/releases/tag/v0.1.0\n"
    )

    def test_hand_edited_section_fails_lint(self):
        """エントリファイルが 1 つも無くても、PR の段階で捕まる。"""
        with EntryDir() as entries:
            entries.write_changelog(self.DIRTY)
            code, err = entries.lint()
        self.assertEqual(code, 1)
        self.assertIn("CHANGELOG.md:9", err)
        self.assertIn("[issue]: https://github.com/shinyaoguri/metaphor/issues/511", err)

    def test_hand_edited_section_fails_check(self):
        with EntryDir() as entries:
            entries.write_changelog(self.DIRTY)
            code, err = entries.check()
        self.assertEqual(code, 1)
        self.assertIn(f"`## [{changelog.UNRELEASED}]`", err)

    def test_collect_still_refuses(self):
        """前倒ししても `collect` 側のガードは残す（手で叩く経路があるため）。"""
        with EntryDir() as entries:
            entries.write_changelog(self.DIRTY)
            entries.write("x.added.md", "- Something new.\n")
            code, err = entries.collect()
        self.assertEqual(code, 1)
        self.assertIn("belong at the bottom of the file", err)

    def test_trailing_definition_block_is_not_flagged(self):
        """末尾の正規な link definition ブロックを誤検出しない（偽陽性側）。

        あのブロックは**最後の版のセクション**の中にあり、`## [Unreleased]` の
        中ではない。実物の CHANGELOG.md は 22 行それを持っている。
        """
        clean = self.DIRTY.replace(
            "- Tutorials now ship as sketches ([#511][issue]).\n"
            "\n"
            "[issue]: https://github.com/shinyaoguri/metaphor/issues/511\n",
            "- Tutorials now ship as sketches "
            "([#511](https://github.com/shinyaoguri/metaphor/issues/511)).\n",
        )
        with EntryDir() as entries:
            entries.write_changelog(clean)
            code, err = entries.lint()
        self.assertEqual(code, 0, err)

    def test_notes_drops_the_definition(self):
        """止める理由そのものの実測: Release body には定義が届かない。"""
        with EntryDir() as entries:
            entries.write_changelog(self.DIRTY)
            body = entries.notes()
        self.assertIn("[#511][issue]", body)
        self.assertNotIn("[issue]: https://github.com/shinyaoguri/metaphor/issues/511", body)


class TestRepositoryIsClean(unittest.TestCase):
    """規則を入れた時点の `changelog.d/` が違反 0 件であること。

    新しい規則が既存の借金を作っていないことの確認であり、以後は「エントリを足す
    PR がその場で捕まる」ことの確認でもある。
    """

    def entries(self):
        for path in sorted((REPO_ROOT / "changelog.d").glob("*.md")):
            if path.name in changelog.NOT_AN_ENTRY:
                continue
            yield path, path.read_text(encoding="utf-8")

    def test_no_relative_links_in_changelog_d(self):
        offenders = [
            f"{path.name}:{lineno}: {target}"
            for path, text in self.entries()
            for lineno, target in changelog.relative_links(text)
        ]
        self.assertEqual(offenders, [])

    def test_no_reference_style_links_in_changelog_d(self):
        offenders = [
            f"{path.name}:{lineno}: {found}"
            for path, text in self.entries()
            for lineno, found in changelog.reference_links(text) + changelog.link_definitions(text)
        ]
        self.assertEqual(offenders, [])

    def test_unreleased_section_holds_no_link_definitions(self):
        """実物の CHANGELOG.md が新しいガードを踏まないこと。

        末尾の link definition ブロックは最後の版のセクション側にあるので、
        `## [Unreleased]` を見るガードとは当たらない。
        """
        path = REPO_ROOT / "CHANGELOG.md"
        lines = path.read_text(encoding="utf-8").split("\n")
        changelog.reject_link_defs_in_unreleased(lines, path)


if __name__ == "__main__":
    unittest.main()
