#!/usr/bin/env python3
"""チュートリアルの公開状況を、frontmatter から入口ドキュメントへ書き出す。

正典は `docs/tutorial/NN-slug.md` の frontmatter（`part` / `title` / `draft`）。
README 群が案内する「どこまで公開されているか」は**生成物**で、手で編集しない
こと（llms.txt / examples index / tutorial snippets と同じ運用）。

埋め込みの書式（表のセルに入れられるよう、開始・本体・終了を 1 行に置く）:

    <!-- tutorial-status: ja-status -->第 1 部〜第 10 部を公開中<!-- /tutorial-status -->

種類は 3 つ:

- `ja-status` / `en-status` — どこまで公開済みで、どこから執筆中かの 1 句
- `ja-links:<接頭辞>` — 公開済みの部への日本語リンクを ` / ` で並べたもの。
  接頭辞は本文から `docs/tutorial/` への相対パス（`tutorial/` など）

あわせて、生成物に落とし込めない 2 つの整合も見る（Issue #584）:

- README.md / README.en.md の部の表 — 公開済みの部への導線があり、執筆中の部
  へは張られていないこと
- docs/tutorial/README.md の章立て表 — 状態の欄が frontmatter と一致すること

生成は決定的（入力が同じなら出力はバイト単位で同じ）。
`--check` で陳腐化検出（差分があれば unified diff を出して exit 1）。
"""

import argparse
import difflib
import re
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TUTORIAL_DIR = REPO_ROOT / "docs/tutorial"

# 公開状況を案内する入口ドキュメント。ここに載っていないファイルのマーカーは
# 更新されないので、案内を増やしたらこの表にも足す。
STATUS_DOCS = (
    "README.md",
    "README.en.md",
    "docs/README.md",
    "docs/README.en.md",
    "Examples/README.md",
)

# 部ごとの表を持つドキュメント（各部へのリンクの有無を見る）。
LINK_DOCS = ("README.md", "README.en.md")

# 章立て表を持つ設計文書（状態の欄を見る）。
OUTLINE_DOC = "docs/tutorial/README.md"

MARKER_RE = re.compile(
    r"<!-- tutorial-status:\s*(?P<kind>[^\s>]+)\s*-->"
    r"(?P<body>.*?)"
    r"<!-- /tutorial-status -->"
)

# `| 第 1 部 入門 | [`01-getting-started.md`](01-getting-started.md) | 公開 |`
OUTLINE_ROW_RE = re.compile(
    r"^\|\s*第\s*(?P<part>\d+)\s*部[^|]*\|[^|]*\|\s*(?P<state>[^|]*?)\s*\|\s*$"
)

PUBLISHED_LABEL = "公開"
DRAFT_LABEL = "執筆中"


class StatusError(Exception):
    """frontmatter か本文の構成が壊れている（利用者が直す必要がある）。"""


@dataclass(frozen=True)
class Part:
    number: int
    title: str
    filename: str
    draft: bool


def parse_frontmatter(text: str, label: str) -> dict[str, str]:
    """先頭の `---` ブロックを `key: value` の辞書として読む。"""
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        raise StatusError(f"{label}: frontmatter が無い")
    fields: dict[str, str] = {}
    for i, line in enumerate(lines[1:], start=2):
        if line.strip() == "---":
            return fields
        key, sep, value = line.partition(":")
        if not sep:
            raise StatusError(f"{label}:{i}: frontmatter が `key: value` でない")
        fields[key.strip()] = value.strip()
    raise StatusError(f"{label}: frontmatter が `---` で閉じられていない")


def tutorial_parts() -> list[Part]:
    """本文ファイルを部番号順に読む。正典はこの frontmatter。

    glob は再帰しないので、英語版（`en/NN-slug.md`、Issue #548）は入らない。
    公開状況の正典は日本語版のままで、部番号が二重に並ぶこともない。
    """
    parts: list[Part] = []
    for path in sorted(TUTORIAL_DIR.glob("[0-9][0-9]-*.md")):
        label = path.relative_to(REPO_ROOT).as_posix()
        fields = parse_frontmatter(path.read_text(encoding="utf-8"), label)
        if "title" not in fields:
            raise StatusError(f"{label}: frontmatter に title が無い")
        # part は省略可（website 側もファイル名から補う）。
        number = int(fields.get("part") or path.name.split("-", 1)[0])
        parts.append(
            Part(
                number=number,
                title=fields["title"],
                filename=path.name,
                draft=fields.get("draft") == "true",
            )
        )
    if not parts:
        raise StatusError(f"{TUTORIAL_DIR.relative_to(REPO_ROOT)} に本文が 1 つも無い")
    numbers = [p.number for p in parts]
    if len(set(numbers)) != len(numbers):
        raise StatusError(f"部番号が重複している: {sorted(numbers)}")
    return sorted(parts, key=lambda p: p.number)


def _contiguous_from_one(numbers: list[int]) -> bool:
    return numbers == list(range(1, len(numbers) + 1))


def ja_status(parts: list[Part]) -> str:
    published = [p.number for p in parts if not p.draft]
    drafts = [p.number for p in parts if p.draft]
    if not published:
        return "まだ公開されていません"
    if _contiguous_from_one(published):
        head = (
            f"第 {published[0]} 部を公開中"
            if len(published) == 1
            else f"第 {published[0]} 部〜第 {published[-1]} 部を公開中"
        )
        if not drafts:
            return head
        if drafts[0] == published[-1] + 1:
            return f"{head}。第 {drafts[0]} 部以降は執筆中"
    else:
        head = "第 " + "・".join(str(n) for n in published) + " 部を公開中"
        if not drafts:
            return head
    return f"{head}。第 " + "・".join(str(n) for n in drafts) + " 部は執筆中"


def en_status(parts: list[Part]) -> str:
    published = [p.number for p in parts if not p.draft]
    drafts = [p.number for p in parts if p.draft]
    if not published:
        return "No parts are published yet"
    if _contiguous_from_one(published):
        head = (
            f"Part {published[0]} is published"
            if len(published) == 1
            else f"Parts {published[0]}–{published[-1]} are published"
        )
        if not drafts:
            return head
        if drafts[0] == published[-1] + 1:
            return f"{head}, Part {drafts[0]} onward is being written"
    else:
        head = "Parts " + ", ".join(str(n) for n in published) + " are published"
        if not drafts:
            return head
    listed = ", ".join(str(n) for n in drafts)
    verb = "is" if len(drafts) == 1 else "are"
    noun = "Part" if len(drafts) == 1 else "Parts"
    return f"{head}, {noun} {listed} {verb} being written"


def ja_links(parts: list[Part], prefix: str) -> str:
    return " / ".join(
        f"[第 {p.number} 部 {p.title}]({prefix}{p.filename})"
        for p in parts
        if not p.draft
    )


def render_marker(kind: str, parts: list[Part], label: str) -> str:
    if kind == "ja-status":
        return ja_status(parts)
    if kind == "en-status":
        return en_status(parts)
    if kind.startswith("ja-links"):
        _, _, prefix = kind.partition(":")
        return ja_links(parts, prefix)
    raise StatusError(f"{label}: 知らない tutorial-status の種類 '{kind}'")


def render_document(text: str, parts: list[Part], label: str) -> str:
    if "<!-- /tutorial-status -->" in MARKER_RE.sub("", text):
        raise StatusError(f"{label}: 開始マーカーの無い <!-- /tutorial-status --> がある")
    return MARKER_RE.sub(
        lambda m: (
            f"<!-- tutorial-status: {m.group('kind')} -->"
            f"{render_marker(m.group('kind'), parts, label)}"
            f"<!-- /tutorial-status -->"
        ),
        text,
    )


def check_links(parts: list[Part]) -> list[str]:
    """公開済みの部へ導線があり、執筆中の部へは張られていないことを見る。"""
    problems: list[str] = []
    for rel in LINK_DOCS:
        text = (REPO_ROOT / rel).read_text(encoding="utf-8")
        for part in parts:
            linked = f"docs/tutorial/{part.filename}" in text
            if not part.draft and not linked:
                problems.append(f"{rel}: 公開済みの第 {part.number} 部への導線が無い")
            if part.draft and linked:
                problems.append(f"{rel}: 執筆中の第 {part.number} 部へ導線が張られている")
    return problems


def check_outline(parts: list[Part]) -> list[str]:
    """章立て表の状態の欄が frontmatter と一致することを見る。"""
    by_number = {p.number: p for p in parts}
    seen: set[int] = set()
    problems: list[str] = []
    for i, line in enumerate(
        (REPO_ROOT / OUTLINE_DOC).read_text(encoding="utf-8").split("\n"), start=1
    ):
        row = OUTLINE_ROW_RE.match(line)
        if not row:
            continue
        number = int(row.group("part"))
        part = by_number.get(number)
        if part is None or number in seen:
            continue
        seen.add(number)
        expected = DRAFT_LABEL if part.draft else PUBLISHED_LABEL
        if row.group("state") != expected:
            problems.append(
                f"{OUTLINE_DOC}:{i}: 第 {number} 部の状態が "
                f"'{row.group('state')}' だが frontmatter では '{expected}'"
            )
    for number in sorted(set(by_number) - seen):
        problems.append(f"{OUTLINE_DOC}: 第 {number} 部が章立て表に無い")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="書き換えずに陳腐化だけ調べる（差分があれば exit 1）",
    )
    args = parser.parse_args()

    try:
        parts = tutorial_parts()
    except StatusError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    stale: list[str] = []
    for rel in STATUS_DOCS:
        doc = REPO_ROOT / rel
        original = doc.read_text(encoding="utf-8")
        try:
            updated = render_document(original, parts, rel)
        except StatusError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1
        if updated == original:
            continue
        if args.check:
            stale.append(rel)
            sys.stdout.writelines(
                difflib.unified_diff(
                    original.splitlines(keepends=True),
                    updated.splitlines(keepends=True),
                    fromfile=f"a/{rel}",
                    tofile=f"b/{rel}",
                )
            )
        else:
            doc.write_text(updated, encoding="utf-8")
            print(f"updated {rel}")

    problems = check_links(parts) + check_outline(parts)

    if stale:
        print(
            "\nerror: 公開状況の案内が古い（正典は docs/tutorial/*.md の "
            "frontmatter）: " + ", ".join(stale),
            file=sys.stderr,
        )
        print(
            "  python3 scripts/generate-tutorial-status.py で再生成してコミットする",
            file=sys.stderr,
        )
    for problem in problems:
        print(f"error: {problem}", file=sys.stderr)

    return 1 if stale or problems else 0


if __name__ == "__main__":
    sys.exit(main())
