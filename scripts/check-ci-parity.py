#!/usr/bin/env python3
"""per-PR CI の各ステップが `make ci-check` に載っているかを台帳で固定する。

`make ci-check` は「push 前にこれを通せば CI は赤くならない」ための 1 コマンドとして
CLAUDE.md / DEVELOPMENT.md が案内している入口です。ところが CI へ新しいステップを足す
たびにその対応づけを直す工程が誰の担当でもなく、**名前だけが CI parity を名乗る**状態に
なっていました (Issue #1020)。起票時点で取りこぼしは 14 本あり、うち 12 本は手元で
そのまま走らせられるものでした。

文章で「両方に足してください」と書いても止まらない形の失敗なので、機械で落とします。
この検査が要求するのは 1 つだけ:

    ci.yml の `build-and-test` ジョブに現れるステップは、すべて下の LEDGER に
    「手元での実体」か「CI 専用である理由」つきで載っていること。

つまり CI にステップを足した人は、**`make ci-check` に入れるか / CI 専用と宣言するかを
必ず一度は決める**ことになります。決めずに素通りする道がありません。

`local` を宣言したエントリはさらに、その実体が **`make ci-check` から到達できる**ことまで
確かめます (Makefile を辿って、prerequisites と `$(MAKE) <target>` の連鎖を展開する)。
台帳に書いただけで配線を忘れる、という次の失敗も同じ 1 本で止まります。

判定できないもの (この検査の対象外):

- `build-and-test` 以外のジョブ — 名前の集合だけを JOB_LEDGER で固定します。ステップの
  中身までは見ません (それらは手元で再現できないジョブか、`make examples-check` のように
  性格の違う入口を持つため)
- ステップの**中身**が手元の実体と同じことまでは見ません。ここが見ているのは配線であって
  等価性ではありません

単体でも実行でき (`python3 scripts/check-ci-parity.py`)、CI と `make static-check` の
両方から走ります。関数はすべて「文字列を受け取って結果を返す」形にしてあるので、
`scripts/tests/test_check_ci_parity.py` が合成入力で規則そのものを固定できます。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = REPO_ROOT / ".github" / "workflows" / "ci.yml"
MAKEFILE = REPO_ROOT / "Makefile"

# `make ci-check` が鏡になるべきジョブ。
MIRRORED_JOB = "build-and-test"

# --- 台帳 --------------------------------------------------------------------
#
# ステップ名 -> ("local", 手元での実体) | ("ci-only", CI でしか走らせられない理由)
#
# "local" の値は 2 通りに書けます:
#   - "make <target>"     -> `make ci-check` から到達できる target であることを確かめる
#   - それ以外の文字列    -> 到達できるレシピ行のどこかに現れることを確かめる
LEDGER: dict[str, tuple[str, str]] = {
    # -- PR のメタデータを読むもの (PR が無いと走らない) --
    "Lint PR title (Conventional Commits)": (
        "ci-only",
        "PR タイトルを API から読む。手元には PR が無い",
    ),
    "Require a changelog.d entry for user-facing PRs": (
        "ci-only",
        "PR のタイトルとラベルを API から読む。手元には PR が無い",
    ),
    "Require visual evidence for drawing changes": (
        "ci-only",
        "PR 本文とラベルを API から読む。手元には PR が無い",
    ),
    # -- CI 内部の分岐・報告 --
    "Detect Source changes": ("ci-only", "後続ステップの起動条件を作る CI 内部の分岐"),
    "Select Xcode": ("ci-only", "ランナーの Xcode 選択。手元は xcode-select 済み"),
    "Upload golden image diffs": ("ci-only", "失敗時に artifact を残すだけ"),
    "Coverage Report": ("ci-only", "カバレッジの集計と報告のみ (合否を作らない)"),
    "Upload coverage report": ("ci-only", "artifact を残すだけ"),
    # -- 外部サービスが要るもの --
    "Check CONTRACT.md identity across repos": (
        "ci-only",
        "metaphor-cli の既定ブランチを GitHub API で引く",
    ),
    # -- ここから下は `make ci-check` が実際に走らせるもの --
    "Lint changelog.d entries": ("local", "python3 scripts/changelog.py lint"),
    "Lint workflows (actionlint)": ("local", "make lint-workflows"),
    "Check CI parity": ("local", "python3 scripts/check-ci-parity.py"),
    "Test generator scripts": ("local", "python3 -m unittest discover -s scripts/tests"),
    "Lint Python scripts": ("local", "make lint-python"),
    "Check cross-repo contract": ("local", "./scripts/check-contract.sh"),
    "Check wire-schema contract": ("local", "make contract-schema"),
    "Check strict concurrency coverage": (
        "local",
        "python3 scripts/check-strict-concurrency.py",
    ),
    "Check for raw print() in Sources": ("local", "python3 scripts/check-no-raw-print.py"),
    "Check doc comment language": (
        "local",
        "python3 scripts/check-doc-comment-language.py",
    ),
    "Check docs links": ("local", "make docs-links-check"),
    "Check that the root manifest has no binary targets": (
        "local",
        "make check-binary-targets",
    ),
    "Check Swift formatting": ("local", "./scripts/lint-swift.sh"),
    "Build": ("local", "swift build -Xswiftc -warnings-as-errors"),
    "Test with Coverage": ("local", "swift test -Xswiftc -warnings-as-errors"),
    # 生成物の鮮度は 1 本にまとまっている (scripts/check-generated-freshness.sh)。
    "Verify shader sources are up to date": ("local", "make freshness-check"),
    "Verify tutorial snippets are up to date": ("local", "make freshness-check"),
    "Verify tutorial publication status is up to date": ("local", "make freshness-check"),
    "Verify tutorial result images are up to date": ("local", "make freshness-check"),
    "Verify reference result images are up to date": ("local", "make freshness-check"),
    "Verify llms.txt is up to date": ("local", "make freshness-check"),
    "Auto-regenerate examples index (PR only)": ("local", "make freshness-check"),
    "Verify reference snippets compile": ("local", "make reference-snippets-check"),
    "Verify DocC builds without warnings": ("local", "make docs-check"),
    "Check reference links in docs": ("local", "make reference-links-check"),
    "Validate AI-facing docs": ("local", "make ai-docs-check"),
}

# ci.yml のジョブ名 -> そのジョブが何者か。`build-and-test` 以外は手元で再現しません。
JOB_LEDGER: dict[str, str] = {
    "build-and-test": "make ci-check が鏡になるジョブ",
    "build-swift-5-10": "最小サポート (Xcode 15.4) でのビルド。手元の Xcode は 1 つ",
    "website-build": "Astro (npm) のビルド。手元は cd website && npm ci && npm run build",
    "examples-detect": "変更された example の検出 (Linux ランナー)",
    "examples-diff-build": "変更された example だけを建てる。手元は make examples-check",
    "ci-gate": "上のジョブを畳む集約ゲート",
}

_JOB_RE = re.compile(r"^  ([A-Za-z0-9_][A-Za-z0-9_-]*):\s*$")
_STEP_NAME_RE = re.compile(r"^      - name: (.+?)\s*$")
# ターゲット行。`.PHONY:` (先頭が `.`) と変数代入は弾く。
_TARGET_RE = re.compile(
    r"^([A-Za-z0-9_][A-Za-z0-9_.\-]*(?:[ \t]+[A-Za-z0-9_][A-Za-z0-9_.\-]*)*)[ \t]*:(?!=)[ \t]*(.*)$"
)
_SUBMAKE_RE = re.compile(r"\$\(MAKE\)((?:[ \t]+--[A-Za-z0-9-]+)*)[ \t]+([A-Za-z0-9_.\-]+)")


def job_names(workflow_source: str) -> list[str]:
    """`jobs:` 直下のジョブ名を、書かれた順に返す。"""
    names: list[str] = []
    in_jobs = False
    for line in workflow_source.splitlines():
        if line.startswith("jobs:"):
            in_jobs = True
            continue
        if not in_jobs:
            continue
        # インデント 0 の別キーが来たら jobs: は終わり。
        if line and not line[0].isspace() and not line.startswith("#"):
            break
        match = _JOB_RE.match(line)
        if match:
            names.append(match.group(1))
    return names


def step_names(workflow_source: str, job: str) -> list[str]:
    """指定ジョブの `- name:` を、書かれた順に返す。

    `with:` の中の `name:` (インデントが深い) や、名前を持たない `- uses:` は拾わない。
    """
    names: list[str] = []
    in_jobs = False
    current: str | None = None
    for line in workflow_source.splitlines():
        if line.startswith("jobs:"):
            in_jobs = True
            continue
        if not in_jobs:
            continue
        if line and not line[0].isspace() and not line.startswith("#"):
            break
        job_match = _JOB_RE.match(line)
        if job_match:
            current = job_match.group(1)
            continue
        if current != job:
            continue
        step_match = _STEP_NAME_RE.match(line)
        if step_match:
            names.append(step_match.group(1))
    return names


def parse_makefile(makefile_source: str) -> dict[str, tuple[list[str], list[str]]]:
    """target -> (prerequisites, レシピ行) を返す。"""
    rules: dict[str, tuple[list[str], list[str]]] = {}
    pending: list[str] = []
    for line in makefile_source.splitlines():
        if line.startswith("\t"):
            for target in pending:
                rules[target][1].append(line.lstrip("\t"))
            continue
        if not line.strip() or line.lstrip().startswith("#"):
            # 空行やコメントはレシピを終わらせない (Make も同じ)。
            continue
        match = _TARGET_RE.match(line)
        if not match:
            pending = []
            continue
        pending = match.group(1).split()
        prereqs = match.group(2).split()
        for target in pending:
            existing = rules.setdefault(target, ([], []))
            existing[0].extend(prereqs)
    return rules


def reachable(makefile_source: str, root: str) -> tuple[set[str], list[str]]:
    """`make <root>` から到達する (target 集合, レシピ行の一覧) を返す。

    辿るのは prerequisites と、レシピ中の `$(MAKE) <target>` の 2 つ。
    """
    rules = parse_makefile(makefile_source)
    seen: set[str] = set()
    recipes: list[str] = []
    stack = [root]
    while stack:
        target = stack.pop()
        if target in seen:
            continue
        seen.add(target)
        prereqs, lines = rules.get(target, ([], []))
        stack.extend(prereqs)
        for line in lines:
            recipes.append(line)
            for match in _SUBMAKE_RE.finditer(line):
                stack.append(match.group(2))
    return seen, recipes


def check(
    workflow_source: str,
    makefile_source: str,
    ledger: dict[str, tuple[str, str]] | None = None,
    job_ledger: dict[str, str] | None = None,
    root: str = "ci-check",
    job: str = MIRRORED_JOB,
) -> list[str]:
    """問題を人が読める行で返す。空なら合格。"""
    ledger = LEDGER if ledger is None else ledger
    job_ledger = JOB_LEDGER if job_ledger is None else job_ledger
    problems: list[str] = []

    jobs = job_names(workflow_source)
    for name in jobs:
        if name not in job_ledger:
            problems.append(
                f"ジョブ '{name}' が scripts/check-ci-parity.py の JOB_LEDGER にありません。"
                " 何者かを 1 行で書き足してください。"
            )
    for name in job_ledger:
        if name not in jobs:
            problems.append(f"JOB_LEDGER の '{name}' は ci.yml にもうありません。消してください。")

    steps = step_names(workflow_source, job)
    if not steps:
        problems.append(
            f"ci.yml の '{job}' ジョブからステップを 1 つも読めませんでした"
            " (ジョブ名かインデントが変わった可能性があります)。"
        )
        return problems

    targets, recipes = reachable(makefile_source, root)
    recipe_text = "\n".join(recipes)

    for name in steps:
        entry = ledger.get(name)
        if entry is None:
            problems.append(
                f"CI ステップ '{name}' が台帳にありません。"
                f" `make {root}` に足して LEDGER へ ('local', 手元での実体) を、"
                " 手元で走らせられないなら ('ci-only', 理由) を書いてください。"
            )
            continue
        kind, value = entry
        if kind != "local":
            continue
        if value.startswith("make "):
            wanted = value.split(None, 1)[1]
            if wanted not in targets:
                problems.append(
                    f"CI ステップ '{name}' は台帳で '{value}' と宣言していますが、"
                    f" target '{wanted}' は `make {root}` から到達できません。"
                )
        elif value not in recipe_text:
            problems.append(
                f"CI ステップ '{name}' は台帳で '{value}' と宣言していますが、"
                f" `make {root}` から到達するレシピに現れません。"
            )

    for name in ledger:
        if name not in steps:
            problems.append(
                f"台帳の '{name}' は ci.yml の '{job}' にもうありません。消してください。"
            )

    return problems


def main() -> int:
    problems = check(
        WORKFLOW.read_text(encoding="utf-8"),
        MAKEFILE.read_text(encoding="utf-8"),
    )
    if problems:
        print("::error::CI と `make ci-check` の対応づけが崩れています (Issue #1020)。")
        for problem in problems:
            print(f"  - {problem}")
        print("")
        print("台帳は scripts/check-ci-parity.py の LEDGER / JOB_LEDGER です。")
        return 1
    steps = step_names(WORKFLOW.read_text(encoding="utf-8"), MIRRORED_JOB)
    local = sum(1 for name in steps if LEDGER[name][0] == "local")
    print(
        f"CI parity: {MIRRORED_JOB} の {len(steps)} ステップ中 {local} 本が"
        f" `make ci-check` に載っています (残り {len(steps) - local} 本は CI 専用と宣言済み)。"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
