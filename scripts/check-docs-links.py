#!/usr/bin/env python3
"""docs の Markdown 相対リンクと ADR 索引の整合を検査する。

`docs/**` は相互参照で結ばれている。ADR は append-only で参照が増え続け（`0014` は
`0001` / `0005` / `0009` / `0012` と `../design/live-viewer.md` を指し、逆に `0001` と
`live-viewer.md` が `0014` を指す）、`docs/design/*.md` も互いに結ばれている。ファイルの
リネームや見出しの変更でリンクが切れても、**踏んだ人が現れるまで誰も気付けない**（Issue
#1044）。`make docs-check` は DocC の警告検査で `docs/adr/` / `docs/design/` の Markdown を
見ておらず、`scripts/check-image-urls.py` は Gyazo 画像専用の週次なので、ここが空白だった。

検査は 2 つ:

1. **相対リンク** — `[text](target)` の `target` が実在するか。外部 URL は対象外
   （ネットワーク依存の flaky を持ち込まない。DocC のリファレンス URL は #987、Gyazo 画像は
   `asset-health.yml` が別途担当する）
2. **ADR 索引** — `docs/adr/README.md` の「既存 ADR」テーブルと `NNNN-*.md` の実ファイルが
   1:1 で、番号が連番か（`docs/adr/README.md` の「書き方 5. 下のテーブルに 1 行追記する」を
   機械で守る）

`CONTRACT.md` / `contract/README.md` は対象外。両リポにバイト同一で複製される identity セット
なので、あちらは相対リンクそのものを禁じる（Issue #1010）＝ 規則が逆向きになる。

単体でも実行でき（`python3 scripts/check-docs-links.py` / `make docs-links-check`）、
判定規則は `scripts/tests/test_check_docs_links.py` が CI で毎 PR 固定する。

Exit code: 0 = 問題なし、1 = 検出あり。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote

sys.path.insert(0, str(Path(__file__).resolve().parent))

from markdown_common import strip_code  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent

# 対象: docs/**/*.md + ルートの主要ドキュメント。
# 対象外: CONTRACT.md / contract/README.md（identity セット。#1010 の担当）、
# website/**（Astro のビルドが持つ）、Sources/**/*.docc（make docs-check の doc: リンク検査）、
# Examples/**/*.md。
ROOT_DOCS = ("README.md", "README.en.md", "DEVELOPMENT.md", "CONTRIBUTING.md", "CLAUDE.md")

# リンク先として許すスキーム。`doc:` は DocC のシンボルリンクで、解決するのは DocC 側。
EXTERNAL_SCHEMES = ("http://", "https://", "mailto:", "doc:", "tel:")

# フェンス・インラインコードの正規表現と `strip_code` は markdown_common が持つ
# （3 本の検査で同じ線引きを使うため。#1183）。
_HEADING_RE = re.compile(r"^(?P<level>#{1,6})\s+(?P<text>.*?)\s*#*\s*$")
_HTML_ANCHOR_RE = re.compile(r"""<a\s[^>]*(?:id|name)\s*=\s*['"](?P<anchor>[^'"]+)['"]""")
# [text](target) / ![alt](target)。target 内の 1 段のカッコまでは許す（URL に現れうる）。
_LINK_RE = re.compile(r"\[(?:[^\[\]]|\[[^\[\]]*\])*\]\((?P<target>[^()]*(?:\([^()]*\)[^()]*)*)\)")
_MD_LINK_TEXT_RE = re.compile(r"\[(?P<text>[^\[\]]*)\]\([^()]*\)")
_ADR_FILE_RE = re.compile(r"^(?P<number>\d{4})-.+\.md$")
_ADR_ROW_RE = re.compile(r"^\|\s*\[(?P<number>\d{4})\]\((?P<target>[^)]+)\)\s*\|")


def slugify(heading_text: str) -> str:
    """見出しを GitHub のアンカー（slug）へ変換する。

    実測で確かめた 3 点を守る。どれも外すと偽陽性になる:

    - 記号を除いた跡の空白は**畳まない**（`## Amendment 2026-08-23 — 再現性で…` は
      `amendment-2026-08-23--再現性で…` と `-` が 2 個になる）
    - 見出しのインラインコードは**中身を残す**（`### \x60frameRate()\x60 sets, ...` は
      `framerate-sets-...`）＝ 本文と違いコードスパンごと落としてはいけない
    - 日本語は Python の `\\w` に含まれるので、追加の文字クラスは要らない

    リポジトリ実体の全 61 ファイル・アンカー 1096 本を GitHub のレンダリング結果
    （`gh api -H "Accept: application/vnd.github.html" /repos/.../contents/<path>` の
    `id="user-content-..."`）と突き合わせて一致を確認している。
    """
    text = _MD_LINK_TEXT_RE.sub(lambda m: m.group("text"), heading_text)
    text = text.replace("`", "")
    text = text.lower()
    text = re.sub(r"[^\w\s-]", "", text, flags=re.UNICODE)
    # 端の空白も畳まない。`### Option A: ...` は記号を除くと末尾に空白が残り、GitHub は
    # それを `-` にする（`option-a-`。docs/adr/template.md で実測）。
    return text.replace(" ", "-")


def anchors_of(path: Path) -> set[str]:
    """リンク先ファイルが持つアンカーの集合。

    同名の見出しには GitHub が `-1` / `-2` と連番を足すので、それも入れる。
    """
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return set()

    anchors: set[str] = set(_HTML_ANCHOR_RE.findall(text))
    seen: dict[str, int] = {}
    for line in strip_code(text, keep_inline_code=True):
        match = _HEADING_RE.match(line)
        if not match:
            continue
        slug = slugify(match.group("text"))
        if not slug:
            continue
        count = seen.get(slug, 0)
        anchors.add(slug if count == 0 else f"{slug}-{count}")
        seen[slug] = count + 1
    return anchors


def link_targets(text: str):
    """本文から (行番号, リンク先) を拾う。コードとして書かれたものは含まない。"""
    for lineno, line in enumerate(strip_code(text), 1):
        for match in _LINK_RE.finditer(line):
            target = match.group("target").strip()
            # `](path "title")` のタイトルと `](<path>)` の山カッコを落とす。
            if target.startswith("<") and ">" in target:
                target = target[1 : target.index(">")]
            else:
                target = target.split()[0] if target.split() else ""
            if target:
                yield lineno, target


def markdown_files(repo_root: Path) -> list[Path]:
    """検査対象の Markdown を返す。"""
    files = sorted(repo_root.glob("docs/**/*.md"))
    files += [repo_root / name for name in ROOT_DOCS if (repo_root / name).is_file()]
    return files


def check_links(repo_root: Path, files: list[Path]) -> list[str]:
    """相対リンクの解決結果を、見つかった順の失敗メッセージで返す。"""
    failures: list[str] = []
    anchor_cache: dict[Path, set[str]] = {}

    def anchors(path: Path) -> set[str]:
        if path not in anchor_cache:
            anchor_cache[path] = anchors_of(path)
        return anchor_cache[path]

    for source in files:
        try:
            text = source.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as error:  # pragma: no cover - 実運用では起きない
            failures.append(f"{source}: 読めません: {error}")
            continue
        where = source.relative_to(repo_root)
        for lineno, target in link_targets(text):
            if target.startswith(EXTERNAL_SCHEMES) or target.startswith("//"):
                continue
            path_part, _, anchor = target.partition("#")
            path_part = unquote(path_part)
            anchor = unquote(anchor)

            if path_part:
                resolved = (source.parent / path_part).resolve()
                try:
                    resolved.relative_to(repo_root)
                except ValueError:
                    failures.append(f"{where}:{lineno}: リポジトリの外を指しています: {target}")
                    continue
                if not resolved.exists():
                    failures.append(f"{where}:{lineno}: リンク先がありません: {target}")
                    continue
            else:
                resolved = source

            if anchor and resolved.suffix == ".md" and resolved.is_file():
                if anchor not in anchors(resolved):
                    failures.append(f"{where}:{lineno}: 見出しがありません: {target}")
    return failures


def check_adr_index(adr_dir: Path) -> list[str]:
    """`docs/adr/README.md` の索引と ADR 実ファイルの 1:1 と連番を検査する。"""
    index = adr_dir / "README.md"
    if not index.is_file():
        return [f"{index}: ADR 索引がありません"]

    files: dict[str, str] = {}
    failures: list[str] = []
    for path in sorted(adr_dir.glob("*.md")):
        match = _ADR_FILE_RE.match(path.name)
        if not match:
            continue
        number = match.group("number")
        if number in files:
            failures.append(f"docs/adr/{path.name}: 番号 {number} が {files[number]} と重複しています")
            continue
        files[number] = path.name

    rows: list[tuple[str, str]] = []
    for line in index.read_text(encoding="utf-8").splitlines():
        match = _ADR_ROW_RE.match(line)
        if match:
            rows.append((match.group("number"), unquote(match.group("target"))))

    listed = {number for number, _ in rows}
    for number, target in rows:
        if number not in files:
            failures.append(f"docs/adr/README.md: 索引の ADR-{number} に実ファイルがありません")
        elif target != files[number]:
            failures.append(
                f"docs/adr/README.md: 索引の ADR-{number} のリンク先が実ファイルと違います "
                f"（索引: {target} / 実体: {files[number]}）"
            )
    if len(listed) != len(rows):
        failures.append("docs/adr/README.md: 索引に同じ番号の行が複数あります")

    for number, name in sorted(files.items()):
        if number not in listed:
            failures.append(f"docs/adr/{name}: 索引（docs/adr/README.md）に行がありません")

    numbers = sorted(int(number) for number in files)
    expected = list(range(1, len(numbers) + 1))
    if numbers != expected:
        missing = sorted(set(expected) - set(numbers))
        failures.append(
            "docs/adr/: 番号が 0001 からの連番になっていません"
            + (f"（欠番: {', '.join(f'{n:04d}' for n in missing)}）" if missing else "")
        )

    ordered = [number for number, _ in rows]
    if ordered != sorted(ordered):
        failures.append("docs/adr/README.md: 索引の行が番号順に並んでいません")

    return failures


def main() -> int:
    repo_root = REPO_ROOT
    failures = check_links(repo_root, markdown_files(repo_root))
    failures += check_adr_index(repo_root / "docs" / "adr")

    if failures:
        print("docs のリンク検査で問題が見つかりました:\n", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        print(
            "\nリンク先のパスは書いたファイルからの相対で解決されます。見出しへのアンカーは"
            "\n記号を除いて小文字化し、空白を 1 つずつ `-` にしたものです"
            "\n（`## A — B` は `a--b`。記号を除いた跡の空白は畳まれません）。",
            file=sys.stderr,
        )
        return 1

    print("docs links: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
