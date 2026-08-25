#!/usr/bin/env python3
"""ドキュメントが張る DocC リファレンス URL が実在するページを指しているか検査する。

チュートリアルをはじめとする Markdown は、API の説明を
`https://shinyaoguri.github.io/metaphor/reference/documentation/<path>` へ外部リンクしている
（220 本前後）。この URL には**シグネチャがそのまま焼き込まれている**ので、引数ラベルが 1 つ
増えただけでリンクは 404 になる。実際 Issue #959 では 4 本が同時に死んでいた（ライトに
`intensity:` が増えた 3 本と、`endGIFRecordAsync(_:)` の別名化で DocC の曖昧性解消サフィックス
`-57dkf` が消えた 1 本）。壊れても CI は緑のままで、気付けるのは「リンクを踏んだ誰か」が
現れたときだけ ＝ 機械で捕まえるべき失敗（Issue #987）。

判定はローカルの DocC 出力に当てる:

1. Markdown から `.../reference/documentation/<path>` を拾う（`ja/` 版も同じ骨格なので同一視。
   日本語リファレンスは英語版から生成された翻訳で、ページの集合は 1:1 — ADR-0011）
2. 末尾の `/` とアンカー・クエリを落とし、`%28` / `%29` を戻す
3. `<docs-dir>/data/documentation/<path>.json` の有無を見る

**公開サイトへ HTTP を投げる方式は採らない**。ネットワーク依存は flaky を持ち込むうえ、
見に行く先が「公開済みのリファレンス」なので、main へ入る前の変更（＝ まさに止めたい
タイミング）を検知できない。ローカル出力に当てれば、その PR が入れようとしている API の姿で
判定できる。実際、この検査を書いた時点で `make docs` の出力と公開サイトの 404 は一致した。

`scripts/check-docs-links.py` とは分けてある。あちらは**ビルド不要**が取り柄で CI の手前に
置かれており、DocC ビルドを前提にする検査を混ぜるとその性質が壊れる。

対象外:

- `CHANGELOG.md` — リリース時点の記述を保存する履歴。当時のリファレンスの姿を指しているので、
  現行のシンボル集合で正誤を決めない（未リリースの `changelog.d/` は逆に対象。集約されて
  履歴になる前なら直せる）
- **コードとして書かれた URL**（フェンス・インラインコード）。URL の**形**を説明するときに
  書く `.../documentation/…` のようなプレースホルダは、踏むためのリンクではない
  （この検査を書いた当日、DEVELOPMENT.md へ足した説明文がそのまま偽陽性になった）。
  逆に言えば、死んだ URL を引き合いに出したいときはコードとして書けばよい

単体でも実行でき（`python3 scripts/check-reference-links.py` / `make reference-links-check`）、
判定規則は `scripts/tests/test_check_reference_links.py` が CI で毎 PR 固定する。

Exit code: 0 = 問題なし、1 = 検出あり。
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from urllib.parse import unquote

sys.path.insert(0, str(Path(__file__).resolve().parent))

from markdown_common import strip_code  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent

# 公開サイトのリファレンスのベース。Makefile の DOCC_BASE_PATH（metaphor/reference）と
# GitHub Pages のホストで決まる。`ja/` は ADR-0011 の日本語版で、英語版と同じ骨格。
_URL_RE = re.compile(
    r"https://shinyaoguri\.github\.io/metaphor/reference/(?:ja/)?documentation/(?P<path>[^\s)\]\"'`<>]*)"
)

# DocC の曖昧性解消サフィックス（`-57dkf`）。同名シンボルが複数あるときだけ付き、
# 片方が消えると URL からも消える ＝ Issue #959 の 4 本目の壊れ方。
_DISAMBIGUATION_RE = re.compile(r"-[0-9a-z]{2,}$")

# 日本語の文末に置かれた素の URL を拾ったときのため、リンクの一部になりえない
# 末尾の約物を落とす。
_TRAILING_PUNCTUATION = ".,、。：:；;!?"

# フェンス・インラインコードの正規表現と `strip_code` は markdown_common が持つ
# （3 本の検査で同じ線引きを使うため。#1183）。

# 走査対象。`website/**` は将来 Markdown が増えたときのために入れてある（現状 README.md のみ）。
SCAN_GLOBS = (
    "docs/**/*.md",
    "Examples/**/*.md",
    "website/**/*.md",
    "Sources/**/*.docc/**/*.md",
    "changelog.d/*.md",
)
ROOT_DOCS = ("README.md", "README.en.md", "DEVELOPMENT.md", "CONTRIBUTING.md", "CLAUDE.md")

# 生成物・依存物の中は見ない（.build には DocC 出力そのものが入る）。
EXCLUDED_DIRS = frozenset({".build", "node_modules", ".git"})


def markdown_files(repo_root: Path) -> list[Path]:
    """検査対象の Markdown を返す（重複なし・パス順）。"""
    found: set[Path] = set()
    for pattern in SCAN_GLOBS:
        for path in repo_root.glob(pattern):
            if not path.is_file():
                continue
            relative = path.relative_to(repo_root)
            if EXCLUDED_DIRS.intersection(relative.parts):
                continue
            found.add(path)
    for name in ROOT_DOCS:
        path = repo_root / name
        if path.is_file():
            found.add(path)
    return sorted(found)


def reference_paths(text: str):
    """本文から (行番号, 書かれたままの path, 正規化した path) を拾う。

    正規化は「アンカー・クエリを落とす → 末尾の `/` と約物を落とす → percent-decode」。
    `.../documentation/` のように path が空になるものは索引ページで、シンボルではないので
    呼び出し側が読み飛ばせるよう空文字のまま返す。
    """
    for lineno, line in enumerate(strip_code(text), 1):
        for match in _URL_RE.finditer(line):
            raw = match.group("path")
            normalized = raw.split("#", 1)[0].split("?", 1)[0]
            normalized = normalized.rstrip(_TRAILING_PUNCTUATION).rstrip("/")
            yield lineno, raw, unquote(normalized)


def symbol_key(page_path: str) -> str:
    """ページのパスから「同じシンボルか」を見るための鍵を作る。

    引数ラベルと曖昧性解消サフィックスを落とした葉の名前。`spotlight(_:_:_:angle:)` と
    `spotlight(_:_:_:angle:intensity:)` は同じ鍵になる ＝ 壊れたリンクの行き先候補を出せる。
    """
    leaf = page_path.rsplit("/", 1)[-1]
    name = leaf.split("(", 1)[0]
    return _DISAMBIGUATION_RE.sub("", name) if "(" not in leaf else name


def suggestions(documentation_dir: Path, page_path: str, *, limit: int = 3) -> list[str]:
    """壊れたリンクの行き先候補を返す（同じシンボル名を持つ実在ページ）。

    まず同じ親ディレクトリを見る（シグネチャが変わった / サフィックスが消えた場合）。
    そこに無ければ全体から同名の葉を探す（型ごと移動した場合）。
    """
    key = symbol_key(page_path)
    if not key:
        return []
    parent_relative = page_path.rsplit("/", 1)[0] if "/" in page_path else ""
    parent = documentation_dir / parent_relative if parent_relative else documentation_dir

    def matches(paths) -> list[str]:
        found = []
        for path in sorted(paths):
            if path.suffix != ".json":
                continue
            relative = path.relative_to(documentation_dir).with_suffix("").as_posix()
            if relative != page_path and symbol_key(relative) == key:
                found.append(relative)
        return found

    if parent.is_dir():
        near = matches(parent.glob("*.json"))
        if near:
            return near[:limit]
    return matches(documentation_dir.rglob(f"{glob_escape(key)}*.json"))[:limit]


def glob_escape(text: str) -> str:
    """glob のメタ文字を無効化する（シンボル名の `[` `]` `?` を字面で探すため）。"""
    return re.sub(r"([\[\]?*])", r"[\1]", text)


def check_reference_links(repo_root: Path, documentation_dir: Path, files: list[Path]):
    """(失敗メッセージ, 拾ったリンク本数) を返す。"""
    failures: list[str] = []
    seen = 0
    for source in files:
        try:
            text = source.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as error:  # pragma: no cover - 実運用では起きない
            failures.append(f"{source}: 読めません: {error}")
            continue
        where = source.relative_to(repo_root)
        for lineno, raw, page_path in reference_paths(text):
            seen += 1
            if not page_path:
                continue
            if (documentation_dir / f"{page_path}.json").is_file():
                continue
            message = f"{where}:{lineno}: リファレンスにそのページがありません: {raw}"
            hits = suggestions(documentation_dir, page_path)
            if hits:
                message += "\n      候補: " + " / ".join(hits)
            failures.append(message)
    return failures, seen


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--docs-dir",
        default=str(REPO_ROOT / ".build" / "docs"),
        help="DocC 出力のルート（既定 .build/docs）",
    )
    args = parser.parse_args()

    documentation_dir = Path(args.docs_dir).expanduser().resolve() / "data" / "documentation"
    if not documentation_dir.is_dir():
        print(
            f"DocC の出力が見つかりません: {documentation_dir}\n"
            "`make docs` でリファレンスを生成してから実行してください"
            "（`make reference-links-check` なら生成込みで走ります）。",
            file=sys.stderr,
        )
        return 1

    files = markdown_files(REPO_ROOT)
    failures, seen = check_reference_links(REPO_ROOT, documentation_dir, files)

    if failures:
        print("リファレンスへのリンク検査で問題が見つかりました:\n", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        print(
            "\nURL にはシグネチャが焼き込まれています。引数ラベルを足した・別名にした・"
            "\nオーバーロードを増減させたときは、本文の URL も併せて直してください"
            "\n（正しい末尾は `.build/docs/data/documentation/` のファイル名がそのまま答えです）。",
            file=sys.stderr,
        )
        return 1

    print(f"reference links: OK ({seen} 本 / {len(files)} ファイル)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
