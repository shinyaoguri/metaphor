#!/usr/bin/env python3
"""Decide whether `main` has anything to release, and how big the bump is.

This is the brain of the weekly release train (.github/workflows/
release-train.yml). The train carries no state: every Monday it looks at the
commits that landed since the latest stable tag and derives the bump from them.
Nothing is recorded at merge time, so there is no label to forget and no queue
to drift — if the run is skipped or fails, the next one reaches the same
conclusion from the same history.

That works because `main` is squash-only and every PR title is linted as
Conventional Commits (ci.yml), so each commit subject on `main` is exactly one
PR title and its type is trustworthy:

    feat            -> minor
    fix, perf       -> patch
    anything else   -> nothing of its own; it ships with the next feat/fix

`major` is never inferred, and what a breaking marker — a `!` in the subject or
a `changelog.d/*.breaking.md` entry — means depends on where the version is:

    0.x       -> the bump is raised to at least `minor`, and the break is
                 announced as a workflow warning (never folded in silently).
                 That is what SemVer gives the minor digit before 1.0, and
                 ADR-0009 keeps it there until the API freeze at 1.0.0.
    1.0.0 on  -> a break means major, and going to a new major is a deliberate
                 call, so it is reported as an escalation (exit code 2). The
                 train fails loudly, a human confirms the bump, and the release
                 goes out with the `release:major` label.

Which rule applies is read from the latest stable tag, so the strict one turns
itself on the moment `v1.0.0` ships — nobody has to remember to edit this file.
Reaching 1.0 at all has non-technical conditions attached
(docs/design/v1-release-plan.md), which is exactly why a break in a `0.x` week
must not be allowed to imply it.

Raising the bump to `minor` also covers a week whose only breaking change rides
a type that releases nothing on its own (`refactor(api)!: …`, the removal half
of a deprecation): without it the removal would ship in no release at all.

Usage:

    release-bump.py                       # bump for main since the latest stable tag
    release-bump.py --explain             # ... and print the reasoning to stderr
    release-bump.py --subject "$TITLE"    # bump for a single PR title
    release-bump.py --fallback patch      # non-releasing types still bump (hotfix path)
    release-bump.py --github-output "$GITHUB_OUTPUT"

Prints the bump (`major` / `minor` / `patch`) on stdout, or nothing when there
is nothing to release. Exit codes: 0 = decided (possibly "nothing"),
2 = a breaking change that needs a major, so it needs a human.
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

# `type(scope)!: summary` — the scope and the breaking marker are optional.
_SUBJECT = re.compile(r"^(?P<type>[a-z]+)(?:\((?P<scope>[^)]*)\))?(?P<breaking>!)?:")

# `vX.` — only the major digit of a tag is ever needed here.
_TAG_MAJOR = re.compile(r"^v?(?P<major>\d+)\.")

# Only these two types justify a release on their own. Everything else
# (docs / chore / ci / refactor / test) rides along with the next one.
BUMP_BY_TYPE = {"feat": "minor", "fix": "patch", "perf": "patch"}

# Ordered weakest to strongest; a range of commits takes the strongest.
_RANK = {"patch": 1, "minor": 2, "major": 3}


def parse_type(subject: str) -> tuple[str | None, bool]:
    """Return `(type, is_breaking)` for a commit subject.

    `type` is None when the subject is not Conventional Commits at all. That is
    not an error: the release commits this workflow itself creates are titled
    `Release vX.Y.Z`, and they must not trigger another release.
    """
    match = _SUBJECT.match(subject.strip())
    if match is None:
        return None, False
    return match.group("type"), match.group("breaking") == "!"


def strongest(bump: str | None, candidate: str | None) -> str | None:
    """The stronger of two bumps, treating `None` as "no release"."""
    if candidate is None:
        return bump
    if bump is None or _RANK[candidate] > _RANK[bump]:
        return candidate
    return bump


def bump_for(subjects) -> tuple[str | None, list[str]]:
    """Return `(bump, breaking_subjects)` for a list of commit subjects."""
    bump = None
    breaking = []
    for subject in subjects:
        commit_type, is_breaking = parse_type(subject)
        if is_breaking:
            breaking.append(subject)
        bump = strongest(bump, BUMP_BY_TYPE.get(commit_type or ""))
    return bump, breaking


def breaking_means_major(tag: str | None) -> bool:
    """Does a break require a major release, given the latest stable tag?

    Only from `1.0.0` on (ADR-0009): while the version is `0.x`, SemVer gives
    the minor digit that role. No tag at all means nothing has been released
    yet, which is as pre-1.0 as it gets. A tag that does not parse is treated
    as `1.x` — the strict branch asks a human instead of guessing.
    """
    if tag is None:
        return False
    match = _TAG_MAJOR.match(tag)
    return match is None or int(match.group("major")) >= 1


def latest_stable_tag(repo: Path) -> str | None:
    """The highest `vX.Y.Z` tag, ignoring prereleases (anything with a `-`).

    Sorted by version, not by commit date: prerelease cycles interleave with
    stable tags, and `git describe` would pick the topologically nearest one.
    """
    out = subprocess.run(
        ["git", "-C", str(repo), "tag", "-l", "v*", "--sort=-v:refname"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    for tag in out.splitlines():
        if tag and "-" not in tag:
            return tag
    return None


def subjects_since(repo: Path, tag: str | None) -> list[str]:
    rev_range = f"{tag}..HEAD" if tag else "HEAD"
    out = subprocess.run(
        ["git", "-C", str(repo), "log", "--format=%s", rev_range],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return [line for line in out.splitlines() if line.strip()]


def pending_breaking_entries(repo: Path) -> list[str]:
    """Uncollected `changelog.d/*.breaking.md` entries.

    A second, independent breaking signal: the author may describe the break in
    `changelog.d/` without marking the PR title with `!`. Either one escalates.
    """
    entries = sorted(repo.joinpath("changelog.d").glob("*.breaking.md"))
    return [path.name for path in entries]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--subject",
        action="append",
        default=None,
        help="Judge these subjects instead of reading git history (repeatable).",
    )
    parser.add_argument(
        "--fallback",
        choices=sorted(_RANK),
        default=None,
        help="Bump to use when no subject calls for a release (hotfix path).",
    )
    parser.add_argument(
        "--repo",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Repository root (default: this script's repository).",
    )
    parser.add_argument(
        "--explain", action="store_true", help="Print the reasoning to stderr."
    )
    parser.add_argument(
        "--github-output",
        type=Path,
        default=None,
        help="Append `bump=<value>` to this file ($GITHUB_OUTPUT).",
    )
    args = parser.parse_args(argv)

    # The latest tag is needed in both modes: it also says which side of 1.0.0
    # the version is on, and that decides what a breaking marker means.
    tag = latest_stable_tag(args.repo)
    if args.subject is not None:
        subjects = args.subject
        source = "the given subjects"
    else:
        subjects = subjects_since(args.repo, tag)
        source = f"{tag}..HEAD" if tag else "the whole history"

    bump, breaking = bump_for(subjects)
    # Only consult changelog.d when judging the actual history: a single PR
    # title says nothing about which entry files are pending.
    if args.subject is None:
        breaking += pending_breaking_entries(args.repo)
    if bump is None and args.fallback:
        bump = args.fallback

    if args.explain:
        counts: dict[str, int] = {}
        for subject in subjects:
            commit_type, _ = parse_type(subject)
            key = commit_type or "(not conventional)"
            counts[key] = counts.get(key, 0) + 1
        print(f"{len(subjects)} commit(s) in {source}:", file=sys.stderr)
        for key in sorted(counts):
            releases = BUMP_BY_TYPE.get(key)
            note = f" -> {releases}" if releases else ""
            print(f"  {counts[key]:3d}  {key}{note}", file=sys.stderr)

    if breaking and breaking_means_major(tag):
        print(
            "::error::Breaking change(s) found — the train does not infer major.\n"
            + "\n".join(f"  {item}" for item in breaking)
            + f"\n{tag} is 1.0 or later, so a break means major "
            "(docs/api-stability-policy.md §4).\n"
            "Confirm the bump and release with the `release:major` label, or "
            "re-word the change if it is not actually breaking.",
            file=sys.stderr,
        )
        return 2
    if breaking:
        bump = strongest(bump, "minor")
        print(
            "::warning::Breaking change(s) ship in this minor — "
            f"{tag or 'nothing released yet'} is still 0.x, where a break "
            "lands in a minor (docs/adr/0009-unfreeze-api-until-1-0.md).\n"
            + "\n".join(f"  {item}" for item in breaking)
            + "\nEach one needs its `### Breaking Changes` CHANGELOG entry and "
            "a migration table. From 1.0.0 on this stops the train instead.",
            file=sys.stderr,
        )

    if args.github_output:
        with args.github_output.open("a", encoding="utf-8") as handle:
            handle.write(f"bump={bump or ''}\n")
    if bump:
        print(bump)
    elif args.explain:
        print("Nothing to release.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
