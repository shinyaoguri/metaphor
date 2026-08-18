#!/usr/bin/env python3
"""Examples/Tutorial/** のコードを docs/tutorial/{,en/}*.md へ埋め込む。

正典は `Examples/Tutorial/<部>/<節>/` に実在する SwiftPM パッケージ。Markdown
側の埋め込みブロックは**生成物**で、手で編集しないこと（llms.txt / examples
index と同じ運用）。チュートリアルの全コードが `make examples-check` と per-PR
CI の差分ビルドでコンパイルを通ることが、これで構造的に保証される（Issue #485）。

英語版（`docs/tutorial/en/NN-slug.md`、Issue #548）も同じ正典から埋める。訳す
のは散文だけで、コードは 1 本を両言語が共有する（`tutorial_documents`）。

埋め込みの書式:

    <!-- tutorial-snippet: 01-GettingStarted/03-SketchSkeleton -->
    (ここは生成物。手で編集しない)
    <!-- /tutorial-snippet -->

開始マーカーの引数は `Examples/Tutorial/` からの相対パス。ブロックの中身は
このスクリプトが毎回まるごと書き換える。書き出されるのは

- パッケージ配下の `*.swift` を（`Package.swift` を除き）パス順に並べた
  ```swift フェンス。2 本以上あるときは各フェンスの前にファイル名を置く
- 実行方法の 1 行（`cd <パス> && swift run`）

あわせて、埋め込みでは直せない ja / en の対応も見る（Issue #956）: `en/NN-slug.md`
があるなら、その `<ref>` の並びが同名の日本語版と**順序込みで**一致すること。
訳すのは散文だけなので、節を落としたり増やしたり順を入れ替えたりすれば、それは
訳のミスであって仕様ではない。

生成は決定的（入力が同じなら出力はバイト単位で同じ）。
`--check` で陳腐化検出（差分があれば unified diff を出して exit 1）。
"""

import argparse
import difflib
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DOCS_DIR = REPO_ROOT / "docs/tutorial"
CODE_DIR = REPO_ROOT / "Examples/Tutorial"
# 英語版の置き場（Issue #548）。ファイル名は日本語版と同じ `NN-slug.md`。
EN_DIR_NAME = "en"

# 設計文書であって本文ではないので、埋め込み走査の対象から外す。
SKIP_DOCS = {"README.md"}

OPEN_RE = re.compile(r"^<!-- tutorial-snippet:\s*(?P<ref>\S+)\s*-->$")
CLOSE_RE = re.compile(r"^<!-- /tutorial-snippet -->$")


class SnippetError(Exception):
    """本文かパッケージの構成が壊れている（利用者が直す必要がある）。"""


def source_files(package_dir: Path) -> list[Path]:
    """パッケージ配下の Swift ソースを、埋め込む順（パス順）で返す。"""
    files = [
        path
        for path in package_dir.rglob("*.swift")
        if path.name != "Package.swift"
        and ".build" not in path.parts
        and ".swiftpm" not in path.parts
    ]
    return sorted(files, key=lambda p: p.relative_to(package_dir).as_posix())


def render_snippet(ref: str) -> str:
    """`<部>/<節>` の埋め込み本体を組み立てる（前後のマーカーは含まない）。"""
    package_dir = CODE_DIR / ref
    if not (package_dir / "Package.swift").is_file():
        raise SnippetError(
            f"snippet ref '{ref}' に対応する SwiftPM パッケージが無い"
            f"（{package_dir.relative_to(REPO_ROOT)}/Package.swift を探した）"
        )

    sources = source_files(package_dir)
    if not sources:
        raise SnippetError(f"snippet ref '{ref}' のパッケージに .swift が 1 つも無い")

    rel_package = package_dir.relative_to(REPO_ROOT).as_posix()
    lines: list[str] = []
    for path in sources:
        if len(sources) > 1:
            lines.append(f"**`{path.relative_to(package_dir).as_posix()}`**")
            lines.append("")
        lines.append("```swift")
        lines.extend(path.read_text(encoding="utf-8").rstrip("\n").split("\n"))
        lines.append("```")
        lines.append("")
    lines.append(f"実行: `cd {rel_package} && swift run`")
    return "\n".join(lines)


def render_document(text: str, doc_label: str) -> str:
    """1 ファイル分の Markdown を、埋め込みブロックだけ差し替えて返す。"""
    out: list[str] = []
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        opened = OPEN_RE.match(line)
        if not opened:
            if CLOSE_RE.match(line):
                raise SnippetError(
                    f"{doc_label}:{i + 1}: 対応する開始マーカーの無い "
                    f"<!-- /tutorial-snippet --> がある"
                )
            out.append(line)
            i += 1
            continue

        ref = opened.group("ref")
        close_at = None
        for j in range(i + 1, len(lines)):
            if CLOSE_RE.match(lines[j]):
                close_at = j
                break
            if OPEN_RE.match(lines[j]):
                break
        if close_at is None:
            raise SnippetError(
                f"{doc_label}:{i + 1}: '{ref}' の埋め込みが "
                f"<!-- /tutorial-snippet --> で閉じられていない"
            )

        out.append(line)
        out.append(render_snippet(ref))
        out.append(lines[close_at])
        i = close_at + 1
    return "\n".join(out)


def ordered_refs(text: str) -> list[str]:
    """本文に現れる `<ref>` を登場順に返す（重複もそのまま残す）。"""
    return [m.group("ref") for m in (OPEN_RE.match(l) for l in text.split("\n")) if m]


def referenced_refs(text: str) -> set[str]:
    return set(ordered_refs(text))


def tutorial_documents() -> list[Path]:
    """埋め込みの対象になる本文。翻訳（`en/`、Issue #548）も最初から見る。

    **コードは訳さない** — `Examples/Tutorial/**` の 1 本を ja / en が共有する。
    埋め込みの対象から en を外すと、英語版だけコードが埋まらないうえに、正典の
    コードが変わったときのドリフト検出も効かなくなる（本文と実行結果が食い違う）。
    画像も同じ考え方で、`generate-tutorial-shots.py` の `doc_paths()` が両方へ
    同じ URL を書き戻す。website の content collection も同じ 2 つの glob を見る
    （`website/src/content.config.ts`）。
    """
    docs = [p for p in DOCS_DIR.glob("*.md") if p.name not in SKIP_DOCS]
    docs += [p for p in DOCS_DIR.glob(f"{EN_DIR_NAME}/*.md") if p.name not in SKIP_DOCS]
    return sorted(docs)


def check_translations() -> list[str]:
    """`en/NN-slug.md` の節構造が日本語版と一致することを見る（Issue #956）。

    見るのは `<ref>` の並びだけで、散文の量も見出しの言い回しも当然違ってよい。
    それでも `<ref>` は「どの節か」を決めるキー（画像の書き戻しもここに乗る）
    なので、落とす・増やす・順を入れ替えるのは訳のミスであって仕様ではない。

    再生成では直せない（本文を書いた人にしか直せない）ので、`--check` の有無に
    かかわらず報告する。
    """
    problems: list[str] = []
    for en_doc in sorted(DOCS_DIR.glob(f"{EN_DIR_NAME}/*.md")):
        if en_doc.name in SKIP_DOCS:
            continue
        en_label = en_doc.relative_to(REPO_ROOT).as_posix()
        ja_doc = DOCS_DIR / en_doc.name
        ja_label = ja_doc.relative_to(REPO_ROOT).as_posix()
        if not ja_doc.is_file():
            problems.append(f"{en_label}: 対応する日本語版 {ja_label} が無い")
            continue
        ja_refs = ordered_refs(ja_doc.read_text(encoding="utf-8"))
        en_refs = ordered_refs(en_doc.read_text(encoding="utf-8"))
        if ja_refs == en_refs:
            continue
        missing = [ref for ref in ja_refs if ref not in en_refs]
        extra = [ref for ref in en_refs if ref not in ja_refs]
        if missing:
            problems.append(
                f"{en_label}: {ja_label} にある節が無い（{', '.join(missing)}）"
            )
        if extra:
            problems.append(
                f"{en_label}: {ja_label} に無い節がある（{', '.join(extra)}）"
            )
        if not missing and not extra:
            problems.append(
                f"{en_label}: 節の順が {ja_label} と違う"
                f"（ja: {' → '.join(ja_refs)} / en: {' → '.join(en_refs)}）"
            )
    return problems


def known_packages() -> list[str]:
    if not CODE_DIR.is_dir():
        return []
    return sorted(
        p.parent.relative_to(CODE_DIR).as_posix()
        for p in CODE_DIR.rglob("Package.swift")
        if ".build" not in p.parts
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="書き換えずに陳腐化だけ調べる（差分があれば exit 1）",
    )
    args = parser.parse_args()

    stale: list[str] = []
    referenced: set[str] = set()
    for doc in tutorial_documents():
        label = doc.relative_to(REPO_ROOT).as_posix()
        original = doc.read_text(encoding="utf-8")
        referenced |= referenced_refs(original)
        try:
            updated = render_document(original, label)
        except SnippetError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1
        if updated == original:
            continue
        if args.check:
            stale.append(label)
            sys.stdout.writelines(
                difflib.unified_diff(
                    original.splitlines(keepends=True),
                    updated.splitlines(keepends=True),
                    fromfile=f"a/{label}",
                    tofile=f"b/{label}",
                )
            )
        else:
            doc.write_text(updated, encoding="utf-8")
            print(f"updated {label}")

    # 本文から一度も参照されていないパッケージは、書きかけか消し忘れ。CI を
    # 止めるほどではない（#488 の執筆中はコードが先に入る）ので警告に留める。
    for ref in known_packages():
        if ref not in referenced:
            print(
                f"warning: Examples/Tutorial/{ref} はどの本文（docs/tutorial/"
                f"{{,en/}}*.md）からも参照されていない",
                file=sys.stderr,
            )

    if stale:
        print(
            "\nerror: 埋め込みが古い（正典は Examples/Tutorial/**）: "
            + ", ".join(stale),
            file=sys.stderr,
        )
        print(
            "  python3 scripts/generate-tutorial-snippets.py で再生成してコミットする",
            file=sys.stderr,
        )

    # ja / en の節構造のずれは再生成では直らないので、別立てで報告する。
    problems = check_translations()
    for problem in problems:
        print(f"error: {problem}", file=sys.stderr)
    if problems:
        print(
            "  訳すのは散文だけ。節（`<!-- tutorial-snippet: <ref> -->`）は日本語版と"
            "同じものを同じ順で置く（docs/tutorial/README.md の「en 側が満たす構造」）",
            file=sys.stderr,
        )

    return 1 if stale or problems else 0


if __name__ == "__main__":
    sys.exit(main())
