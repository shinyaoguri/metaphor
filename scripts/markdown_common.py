#!/usr/bin/env python3
"""Markdown を検査するスクリプトが共有する前処理。

`scripts/check-docs-links.py` / `scripts/check-reference-links.py` /
`scripts/changelog.py` は、どれも「Markdown からリンクや URL を拾って実在を確かめる」
検査です。3 本とも**コードとして書かれた部分は見ない**という同じ線引きを持つので、
その線引き（`strip_code` とフェンス・インラインコードの正規表現）だけをここに置きます。

## なぜ 1 本にするのか

複製そのものより、**片方だけ直る**のが問題でした（#1183）。実際 `keep_inline_code` は
`check-docs-links.py` が後から実測で獲得した分岐で、他 2 本には伝わっていません。
同じ種類の学びが次に出たとき、3 箇所すべてに反映される保証はどこにもない ——
というのが寄せる理由です。3 本目を足した #1181 の時点では別レーンが 2 本を触って
いたため意図的に見送っており、ここでその宿題を返します。

## 何を置き、何を置かないか

置くのは**Markdown の構文をどう読むか**だけです。「どのファイルを走査するか」
（`markdown_files` / `SCAN_GLOBS` / `ROOT_DOCS`）と「リンクをどう拾うか」
（`_LINK_RE` / `ENTRY_LINK_RE`）は**意図的に各スクリプトが持ちます**:

- 走査範囲は 3 本で違う（`check-docs-links.py` は `docs/**` + ルート文書、
  `check-reference-links.py` は `Examples` / `website` / `.docc` / `changelog.d` まで、
  `changelog.py` は `changelog.d/*.md` のみ）。構文の部品と方針を同じ箱に入れると、
  次に片方の範囲を広げたい人が両方を動かしてしまう
- リンクの正規表現は**似ているが同一ではない**。`changelog.py` の `ENTRY_LINK_RE` は
  先頭に `!?` を持ち、画像形式でマッチの開始位置が変わる。寄せると挙動が動くので、
  これは refactor ではなく別の判断が要る変更として切り離してある
"""

from __future__ import annotations

import re

# フェンス（``` / ~~~）の開始・終了。3 バックティック以上・チルダの両方に対応し、
# 開いたのと同じ種類でしか閉じない（`marker` の先頭 1 文字で判定する）。
FENCE_RE = re.compile(r"^\s*(?P<marker>```+|~~~+)")

# インラインコード。バックティックの本数を後方参照で揃えるので、`` `a` `` のように
# 中にバックティックを含む書き方でも正しい範囲で閉じる。
INLINE_CODE_RE = re.compile(r"(?P<ticks>`+)(?P<code>.*?)(?P=ticks)")


def strip_code(text: str, *, keep_inline_code: bool = False) -> list[str]:
    """コードを落とした行の一覧を返す（行番号を保つため空行に置き換える）。

    3 本の検査が共通して避けたい偽陽性は「**コードとして書かれたものを、踏むための
    リンクだと読んでしまう**」ことです。それぞれ違う形で踏んでいます:

    - 説明文中の `` `[こちら](...)` `` を「リンク先が無い」と誤検出する
      （`check-docs-links.py`。実例: docs/adr/0008-docc-reference-images-via-gyazo.md）
    - URL の**形**を説明するプレースホルダ（`.../documentation/…`）を「そんなページは
      無い」と誤検出する（`check-reference-links.py`）。裏を返せば、死んだ URL を
      引き合いに出したいときはコードとして書けばよい、という逃げ道でもある
    - パスに*言及*するだけのエントリ —— ``- `image()` no longer resolves `../foo`.``
      —— を相対リンクと読んでしまう（`changelog.py`）

    `keep_inline_code=True` は見出しを読むとき用。GitHub の slug はコードスパンの
    **中身を残す**ので、アンカーを組み立てる側でインラインコードごと落とすと偽陽性に
    なる（実例: docs/processing-migration-guide.md の ``### `frameRate()` sets, ...``）。
    いま使うのは `check-docs-links.py` の見出し走査だけなので既定は `False` ——
    残り 2 本の従来の挙動がそのまま既定になる。

    フェンスは `keep_inline_code` に関わらず落とす。シェルの `# コメント` を見出しと
    取り違えないため。
    """
    lines: list[str] = []
    fence: str | None = None
    for line in text.splitlines():
        match = FENCE_RE.match(line)
        if fence is None:
            if match:
                fence = match.group("marker")[0]
                lines.append("")
                continue
            lines.append(line if keep_inline_code else INLINE_CODE_RE.sub("", line))
        else:
            if match and match.group("marker")[0] == fence:
                fence = None
            lines.append("")
    return lines
