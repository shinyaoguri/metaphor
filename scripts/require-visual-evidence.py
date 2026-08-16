#!/usr/bin/env python3
"""Fail a PR that changes what gets drawn without showing what it now draws.

CLAUDE.md asks for before/after images on PRs that change the rendered result
(and a GIF when the *motion* changes). Until now that was regulation only: a
PR could change `TextRenderer` and merge with nothing to look at, and nobody
found out. `main` is squash-only, so the evidence is not recoverable later —
the branch is gone and the PR body is the commit body. Whatever was not
written down at merge time is gone for good.

This is an error, not a warning, and it lives inside an already-required job
for the reason spelled out in ci.yml: auto-merge merges the moment the
required checks are green, so a non-required job going red is never seen by
anyone (Issue #411).

Which paths count is not a guess. Taking the PRs that actually changed the
picture and the ones that did not (Issue #631):

    #591 text() upside down      Drawing/TextRenderer.swift        -> asked
    #575 HUD invisible           UI/PerformanceHUD.swift           -> asked
    #609 loadModel normalize     Sketch/Sketch+3D.swift            -> asked
    #592 MIDI data byte range    MetaphorNetwork/                  -> not asked
    #628 example shot plumbing   (no Sources change)               -> not asked

`Core/` is deliberately NOT in the list even though #609 touched it: it holds
plenty that never reaches a pixel, and that PR is caught by `Sketch/` anyway.
A directory earns its place by being one where a change is *usually* visible,
not by being one where a visible change is *possible*.

The judgement call stays with the author, the same way `no-changelog` works
for `require-changelog-entry.py`: a `no-visual-change` label says "this one
genuinely does not change the picture" and the check passes, leaving that
decision recorded on the PR instead of nowhere.

Usage (the changed files come in on stdin, one path per line). The list has to
come from the merge base, not from a two-dot diff against the base tip — see
`scripts/pr-changed-files.sh` for why (Issue #642):

    scripts/pr-changed-files.sh "$BASE" "$HEAD" -- 'Sources/*' \\
        | python3 scripts/require-visual-evidence.py \\
              --body "$BODY" --label "$LABEL" ...

Exit codes: 0 = satisfied or not applicable, 1 = evidence missing.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import PurePosixPath

# Directories under Sources/MetaphorCore/ where a change is normally visible.
# Keep this list short and evidence-backed — every entry widens how often the
# check fires, and a check that fires on work it should not is one people learn
# to wave through with the label.
VISUAL_DIRS = (
    "Drawing",
    "Sketch",
    "Shaders",
    "UI",
    "PostProcess",
    "Particle",
    "Geometry",
)

# The label that records "this does not change the picture" as a decision.
SKIP_LABEL = "no-visual-change"

# Gyazo is the canonical host (ADR-0008 / ADR-0010: images are never committed
# to the repository). GitHub's own attachment hosts are accepted too — dragging
# an image onto the PR box does not commit anything to the repo either, and
# refusing it would only teach people to work around the check.
#
# This repository's own raw URLs count as well (Issue #843). ADR-0008 /
# ADR-0010 forbid *committing* an image; *referencing* a generated image that
# is already in the tree (a golden PNG, an example shot) is a different act,
# and DEVELOPMENT.md tells authors to do exactly that. Re-uploading it to
# Gyazo would only copy the same picture into an append-only asset store, so
# the docs and the check were simply contradicting each other.
#
# Two constraints stop that from hollowing the check out:
#
#   - The repository is pinned. `raw.githubusercontent.com/<anyone>/<any>` is
#     no more evidence than `example.com`.
#   - Only the forms that fetch image *bytes* count. `/raw/` and
#     `blob/…?raw=1` redirect to raw.githubusercontent.com and render as
#     images in the body; a bare `blob/` link opens a *page*, so accepting it
#     would turn every "look at this file" link into evidence. The extension
#     is required for the same reason — raw.githubusercontent.com serves the
#     whole tree, and a link to a `.swift` file is not a picture.
_REPO = r"shinyaoguri/metaphor"
# What `make example-shots` / `make reference-shots` / the golden tests write.
_IMAGE_EXT = r"\.(?:png|jpe?g|gif|webp)"
_IMAGE_HOSTS = (
    r"i\.gyazo\.com",
    r"gyazo\.com/[0-9a-f]{32}",
    r"user-images\.githubusercontent\.com",
    r"github\.com/user-attachments/assets",
    rf"raw\.githubusercontent\.com/{_REPO}/[^\s)]*{_IMAGE_EXT}",
    rf"github\.com/{_REPO}/raw/[^\s)]*{_IMAGE_EXT}",
    rf"github\.com/{_REPO}/blob/[^\s)]*{_IMAGE_EXT}\?(?:[^\s)]*&)?raw=(?:true|1)",
)
_IMAGE_RE = re.compile("|".join(_IMAGE_HOSTS), re.IGNORECASE)


def is_visual_path(path: str) -> bool:
    """True for a file whose change normally changes what gets drawn."""
    parts = PurePosixPath(path).parts
    if len(parts) < 4:
        return False
    if parts[0] != "Sources" or parts[1] != "MetaphorCore":
        return False
    return parts[2] in VISUAL_DIRS


def has_evidence(body: str) -> bool:
    """True when the PR body links at least one image."""
    return bool(_IMAGE_RE.search(body or ""))


def main(argv: list[str] | None = None, stdin=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--body", default="", help="The PR body.")
    parser.add_argument(
        "--label",
        action="append",
        default=[],
        help=f"A label on the PR (repeatable). `{SKIP_LABEL}` skips the check.",
    )
    args = parser.parse_args(argv)

    stream = sys.stdin if stdin is None else stdin
    changed = [line.strip() for line in stream.read().splitlines() if line.strip()]

    visual = [path for path in changed if is_visual_path(path)]
    if not visual:
        print("描画に効くファイルを触っていないため、視覚証跡は要求しません。")
        return 0

    shown = ", ".join(visual[:5]) + (" ほか" if len(visual) > 5 else "")
    if has_evidence(args.body):
        print(f"視覚証跡あり — 対象: {shown}")
        return 0

    if SKIP_LABEL in args.label:
        # A notice, not silence: the skip should be visible in the run log as
        # well as on the PR.
        print(
            f"::notice::描画に効くファイル（{shown}）を触っていますが、"
            f"`{SKIP_LABEL}` ラベルが付いているため視覚証跡を要求しません。"
        )
        return 0

    print(
        f"::error::描画に効くファイルを触っています（{shown}）が、"
        "PR 本文に画像がありません。\n"
        "squash マージなのでブランチは消え、PR 本文がそのまま履歴に残る唯一の"
        "記録になります。後から足せません。\n"
        "  1. before/after を撮って PR 本文に貼る"
        "（**動きが変わるなら GIF も**。手順は DEVELOPMENT.md「PR に見た目の"
        "証跡を載せる」。新しく撮った画像はリポジトリにコミットせず Gyazo へ。"
        "ゴールデン PNG や example の実行結果のように既にコミット済みのものは"
        "そのまま raw URL で貼れます）\n"
        f"  2. 本当に絵が変わらないなら PR に `{SKIP_LABEL}` ラベルを貼る\n"
        "どちらの場合も、直したあと `gh run rerun --failed <run-id>` だけで通ります"
        "（本文とラベルは実行時に API から引くので push は不要です）。",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
