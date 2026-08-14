#!/usr/bin/env python3
"""website のビルド入力が Documentation ワークフローの起動条件に入っているか検査する。

website（Astro）はチュートリアル本文のコピーを持たず、リポジトリルートの
`docs/tutorial/` を content collection として直接読む（`website/src/content.config.ts`
の glob loader の `base`）。一方 `.github/workflows/docs.yml` は `on.push.paths` で
起動対象を絞っているため、**読み込み元を paths に足し忘れると本文だけを変えた push で
サイトが再デプロイされない**（Issue #554）。取りこぼしても CI は緑のまま、公開サイトだけ
が古い、という気付けない壊れ方をする。

そこで website 側の宣言（loader の `base`）を正本として、docs.yml の paths がそれを
覆っているかを突き合わせる。website 配下は `website/**` が丸ごと覆うので対象外。

単体でも実行でき（`python3 scripts/check-docs-workflow-paths.py`）、リポジトリ実体に
対する検査は `scripts/tests/test_check_docs_workflow_paths.py` が CI で毎 PR 走らせる。
"""

from __future__ import annotations

import posixpath
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CONTENT_CONFIG = REPO_ROOT / "website" / "src" / "content.config.ts"
DOCS_WORKFLOW = REPO_ROOT / ".github" / "workflows" / "docs.yml"

# glob loader の `base: '../docs/tutorial'`。クォートはシングル / ダブルの両方を許す。
_BASE_RE = re.compile(r"""\bbase:\s*(['"])(?P<path>[^'"]+)\1""")


def collection_bases(config_source: str) -> list[str]:
    """content collection の loader が読む base を、書かれたまま（website 相対）返す。"""
    return [m.group("path") for m in _BASE_RE.finditer(config_source)]


def external_build_inputs(config_source: str) -> list[str]:
    """website の外にあるビルド入力を、リポジトリルート相対に正規化して返す。

    website 配下の base（`./src/...` など）は docs.yml の `website/**` が覆うので落とす。
    """
    inputs: list[str] = []
    for base in collection_bases(config_source):
        normalized = posixpath.normpath(posixpath.join("website", base))
        if normalized == "website" or normalized.startswith("website/"):
            continue
        if normalized.startswith("../") or normalized.startswith("/"):
            # website の外どころかリポジトリの外。ワークフローでは扱えない。
            raise ValueError(f"base がリポジトリ外を指しています: {base}")
        if normalized not in inputs:
            inputs.append(normalized)
    return inputs


def workflow_push_paths(workflow_source: str) -> list[str]:
    """docs.yml の `on.push.paths` に並ぶパターンを返す。

    YAML パーサに依存しない（PyYAML はランナーによって有無が変わる）。docs.yml の
    paths ブロックは `- 'パターン'` が並ぶだけなので、インデントで区切って読む。
    """
    lines = workflow_source.splitlines()
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped != "paths:":
            continue
        indent = len(line) - len(line.lstrip())
        patterns: list[str] = []
        for entry in lines[index + 1 :]:
            if not entry.strip():
                continue
            entry_indent = len(entry) - len(entry.lstrip())
            if entry_indent <= indent or not entry.lstrip().startswith("- "):
                break
            patterns.append(entry.lstrip()[2:].strip().strip("'\""))
        return patterns
    return []


def is_covered(build_input: str, patterns: list[str]) -> bool:
    """ビルド入力（ディレクトリ）が paths のいずれかに丸ごと覆われるか。

    判定は「そのディレクトリ配下の変更が必ず起動条件に当たるか」。`docs/tutorial/**`
    のような末尾ワイルドカードだけを配下指定として扱い、`docs/*.md` のような部分一致
    は覆えていないものとして扱う（覆えているかの判定に迷う書き方を通さない）。
    """
    for pattern in patterns:
        prefix = pattern
        for suffix in ("/**/*", "/**"):
            if prefix.endswith(suffix):
                prefix = prefix[: -len(suffix)]
                break
        else:
            continue
        if "*" in prefix:
            continue
        if build_input == prefix or build_input.startswith(prefix + "/"):
            return True
    return False


def find_uncovered(config_source: str, workflow_source: str) -> list[str]:
    """paths に覆われていないビルド入力を返す。空なら整合している。"""
    patterns = workflow_push_paths(workflow_source)
    return [
        build_input
        for build_input in external_build_inputs(config_source)
        if not is_covered(build_input, patterns)
    ]


def main() -> int:
    uncovered = find_uncovered(
        CONTENT_CONFIG.read_text(encoding="utf-8"),
        DOCS_WORKFLOW.read_text(encoding="utf-8"),
    )
    if uncovered:
        print("FAIL: website のビルド入力が docs.yml の on.push.paths に入っていません")
        for build_input in uncovered:
            print(f"  - {build_input} → paths に '{build_input}/**' を足してください")
        print(f"  ({CONTENT_CONFIG.relative_to(REPO_ROOT)} の loader base が正本)")
        return 1
    print("OK: website のビルド入力はすべて docs.yml の on.push.paths に入っています")
    return 0


if __name__ == "__main__":
    sys.exit(main())
