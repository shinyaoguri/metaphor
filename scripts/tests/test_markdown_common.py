#!/usr/bin/env python3
"""Unit tests for scripts/markdown_common.py.

Run from the repository root:

    python3 -m unittest discover -s scripts/tests

`strip_code` は 3 本の検査（`check-docs-links.py` / `check-reference-links.py` /
`changelog.py`）が共有する前処理で、#1183 でここへ寄せた。**寄せる前は 3 本のテストが
間接的に覆うだけで、`strip_code` を直に呼ぶテストは 1 つも無かった** —— つまり
「コードとして書かれたものは見ない」という線引きそのものは、どこにも固定されて
いなかった。1 箇所になったいま、その線引きをここで固定する。

とくに `keep_inline_code` は `check-docs-links.py` が実測で獲得した分岐で、いまも
呼ぶのはそこ 1 本だけ。**使う人が 1 人しかいない引数は、消しても 3 本のうち 2 本は
緑のまま**なので、ここで名指しで守る（Issue が言う「片方だけ直る」の裏返し）。
"""

import importlib.util
import sys
import unittest
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "markdown_common.py"
_spec = importlib.util.spec_from_file_location("markdown_common", _SCRIPT)
common = importlib.util.module_from_spec(_spec)
sys.modules["markdown_common"] = common
_spec.loader.exec_module(common)

strip_code = common.strip_code


class StripCodeTests(unittest.TestCase):
    def test_line_numbers_survive(self) -> None:
        """行は落とさず空行に置き換える（検査は行番号で報告するため）。"""
        text = "a\n```\ncode\n```\nb"
        self.assertEqual(strip_code(text), ["a", "", "", "", "b"])
        self.assertEqual(len(strip_code(text)), len(text.splitlines()))

    def test_inline_code_is_removed_by_default(self) -> None:
        """既定ではインラインコードごと落とす（3 本のうち 2 本の従来の挙動）。"""
        self.assertEqual(strip_code("see `[here](/nope.md)` for details"), ["see  for details"])

    def test_inline_code_kept_when_requested(self) -> None:
        """`keep_inline_code=True` は行をそのまま返す。"""
        line = "see `[here](/nope.md)` for details"
        self.assertEqual(strip_code(line, keep_inline_code=True), [line])

    def test_heading_with_inline_code_keeps_its_text(self) -> None:
        """#1183 が名指しした実測由来の分岐。

        GitHub の slug はコードスパンの**中身を残す**ので、見出しを読むときに
        インラインコードごと落とすとアンカーが偽陽性になる
        （docs/processing-migration-guide.md の実例）。
        """
        heading = "### `frameRate()` sets, `frameCount` reads"
        self.assertEqual(strip_code(heading, keep_inline_code=True), [heading])
        # 既定では中身ごと消えるので、アンカーを組み立てる側には使えない。
        self.assertEqual(strip_code(heading), ["###  sets,  reads"])

    def test_fences_are_dropped_even_when_inline_code_is_kept(self) -> None:
        """フェンスは `keep_inline_code` に関わらず落とす。

        落とさないとシェルの `# コメント` が見出しに化ける。
        """
        text = "# real heading\n```sh\n# not a heading\n```"
        self.assertEqual(strip_code(text, keep_inline_code=True), ["# real heading", "", "", ""])

    def test_tilde_fence(self) -> None:
        """`~~~` も フェンスとして扱う。"""
        self.assertEqual(strip_code("~~~\n[x](/nope.md)\n~~~"), ["", "", ""])

    def test_fence_is_closed_only_by_its_own_marker(self) -> None:
        """``` で開いたフェンスは ~~~ では閉じない（種類を取り違えない）。"""
        text = "```\n~~~\n[x](/nope.md)\n```\nafter"
        self.assertEqual(strip_code(text), ["", "", "", "", "after"])

    def test_indented_fence(self) -> None:
        """字下げされたフェンス（リスト中のコードブロック）も拾う。"""
        text = "- item\n    ```\n    [x](/nope.md)\n    ```\n- next"
        self.assertEqual(strip_code(text), ["- item", "", "", "", "- next"])

    def test_longer_backtick_run_opens_a_fence(self) -> None:
        """4 本以上のバックティックでもフェンスとして開く。"""
        self.assertEqual(strip_code("````\ncode\n````\nafter"), ["", "", "", "after"])

    def test_nested_fence_closes_the_outer_one(self) -> None:
        """**既知の制限**: 閉じ判定はマーカーの 1 文字目しか見ない（#1188）。

        CommonMark は「開いた本数以上でしか閉じない」と決めているので、```` の中の
        ``` は本来ただの中身。いまの実装は外側を閉じてしまい、以降が検査対象に戻る。

        寄せる前の 3 実装すべてが同じ挙動で、#1183 の共通化でも変えていない
        （全 Markdown 107 本での出力が before / after で完全一致）。**いまの
        リポジトリに ```` を使った文書は 1 本も無い**ので実害はまだ無いが、
        フェンスの入れ子を説明する文書を書いた日に踏む。直すのは #1188。
        """
        text = "````\n```\n[x](/nope.md)\n````\nafter"
        self.assertEqual(strip_code(text), ["", "", "[x](/nope.md)", "", ""])

    def test_inline_code_closes_on_matching_backtick_count(self) -> None:
        """バックティックの本数を後方参照で揃えるので、中に ` を含む書き方も閉じる。"""
        self.assertEqual(strip_code("a ``b `c` d`` e"), ["a  e"])

    def test_unterminated_fence_swallows_the_rest(self) -> None:
        """閉じ忘れたフェンスは以降を全部落とす（検査を鳴らすより黙るほうを選ぶ）。"""
        self.assertEqual(strip_code("a\n```\nb\nc"), ["a", "", "", ""])

    def test_empty_input(self) -> None:
        self.assertEqual(strip_code(""), [])


class RegexTests(unittest.TestCase):
    """3 本が同じ正規表現を使っていることの担保（名前を変えたら気付ける）。"""

    def test_fence_re_matches_both_markers(self) -> None:
        self.assertTrue(common.FENCE_RE.match("```swift"))
        self.assertTrue(common.FENCE_RE.match("~~~"))
        self.assertTrue(common.FENCE_RE.match("   ```"))
        self.assertIsNone(common.FENCE_RE.match("``not a fence"))

    def test_fence_re_reports_the_marker(self) -> None:
        self.assertEqual(common.FENCE_RE.match("````sh").group("marker"), "````")

    def test_inline_code_re_is_non_greedy(self) -> None:
        self.assertEqual(common.INLINE_CODE_RE.sub("", "`a` and `b`"), " and ")


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
