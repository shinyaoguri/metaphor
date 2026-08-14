#!/usr/bin/env python3
"""Fail a PR that ships a user-facing change without a `changelog.d/` entry.

`changelog.py lint` deliberately does NOT require an entry to exist: whether a
change is user-facing is a judgement call CI cannot make, and internal-only
work legitimately ships without one (Issues #335 / #404). The cost of that is
paid later — a `feat` / `fix` PR merges with nothing written down, and the
**weekly release train** is what discovers it, on Monday, by refusing to leave
the station (`changelog.py check`). The person who has to fix it and the person
who finds out are a week apart (Issue #461).

This brings the question forward to the PR, using the same rule the train
already applies:

    the PR title says this change releases  ->  it has to say what changed

"releases" is not a second list of types maintained here — it is
`release-bump.py`'s `BUMP_BY_TYPE` (feat -> minor, fix / perf -> patch),
imported directly so the two can never drift. A breaking marker (`!`) requires
an entry whatever the type, since a break is exactly what an upgrader needs
told.

The judgement call stays with the author: a `no-changelog` label says "this one
genuinely has nothing to write" and the check passes, leaving that decision
recorded on the PR instead of nowhere.

Usage (the added files come in on stdin, one path per line). The list has to
come from the merge base, not from a two-dot diff against the base tip: a
release deletes every `changelog.d/*.md`, so two-dot would report those as
files this PR added — see `scripts/pr-changed-files.sh` (Issue #642):

    scripts/pr-changed-files.sh "$BASE" "$HEAD" \\
            --diff-filter=A -- 'changelog.d/*.md' \\
        | python3 scripts/require-changelog-entry.py \\
              --subject "$TITLE" --label "$LABEL" ...

Exit codes: 0 = satisfied or not applicable, 1 = entry missing.
"""

from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent


def _load(name: str, filename: str):
    """Import a sibling script whose filename is not a valid module name."""
    spec = importlib.util.spec_from_file_location(name, _SCRIPTS / filename)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


_release_bump = _load("release_bump", "release-bump.py")
_changelog = _load("changelog", "changelog.py")

ENTRY_DIR = "changelog.d"
# The label that records "no entry needed" as a deliberate decision.
SKIP_LABEL = "no-changelog"


def is_entry(path: str) -> bool:
    """True for a file that counts as a changelog entry.

    Only the *location* and extension are checked. Whether the name is
    well-formed (`<slug>.<category>.md`) is `changelog.py lint`'s job, which
    runs in the same CI step group — duplicating it here would report the same
    mistake twice with different wording.
    """
    parts = Path(path).parts
    if len(parts) != 2 or parts[0] != ENTRY_DIR:
        return False
    name = parts[1]
    return name.endswith(".md") and name not in _changelog.NOT_AN_ENTRY


def entry_required(subject: str) -> tuple[bool, str]:
    """Whether `subject` describes a change that has to be written down."""
    commit_type, breaking = _release_bump.parse_type(subject)
    if commit_type is None:
        # Not Conventional Commits at all. The PR-title lint in ci.yml owns
        # that failure; reporting it here too would just add noise.
        return False, "PR タイトルが Conventional Commits 形式ではありません"
    if breaking:
        return True, f"`{commit_type}!` は破壊的変更です"
    bump = _release_bump.BUMP_BY_TYPE.get(commit_type)
    if bump:
        return True, f"`{commit_type}` は単独でリリースを起こします（{bump}）"
    return False, f"`{commit_type}` は単独ではリリースを起こしません"


def main(argv: list[str] | None = None, stdin=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--subject", required=True, help="The PR title (= the squashed commit subject)."
    )
    parser.add_argument(
        "--label",
        action="append",
        default=[],
        help=f"A label on the PR (repeatable). `{SKIP_LABEL}` skips the check.",
    )
    args = parser.parse_args(argv)

    stream = sys.stdin if stdin is None else stdin
    added = [line.strip() for line in stream.read().splitlines() if line.strip()]

    required, why = entry_required(args.subject)
    if not required:
        print(f"changelog.d エントリは不要です: {why}。")
        return 0

    entries = [path for path in added if is_entry(path)]
    if entries:
        print(f"{why} — エントリあり: {', '.join(entries)}")
        return 0

    if SKIP_LABEL in args.label:
        # A notice, not silence: the skip should be visible in the run log as
        # well as on the PR.
        print(
            f"::notice::{why}が、`{SKIP_LABEL}` ラベルが付いているため "
            "changelog.d エントリを要求しません。"
        )
        return 0

    print(
        f"::error::{why}が、この PR は `{ENTRY_DIR}/` にエントリを追加していません。\n"
        "リリース時ではなく今ここで書いてください（週次トレインはエントリが無いと"
        "月曜に発車できません）。\n"
        "  1. `changelog.d/<slug>.<category>.md` を足す"
        "（category: breaking / added / changed / deprecated / removed / fixed / security。"
        "書き方は changelog.d/README.md）\n"
        f"  2. 本当に書くことが無いなら PR に `{SKIP_LABEL}` ラベルを貼る\n"
        "どちらの場合も、直したあと `gh run rerun --failed <run-id>` だけで通ります"
        "（タイトルとラベルは実行時に API から引くので push は不要です）。",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
