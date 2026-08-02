#!/usr/bin/env python3
"""Keep a Changelog helper for CHANGELOG.md.

Three subcommands, all driven by .github/workflows/release.yml:

    changelog.py check
        Fail when the `## [Unreleased]` section is missing, duplicated, or has
        no entries. Runs at the very start of the release job, before anything
        irreversible (branch push, tag, GitHub Release) has happened.

    changelog.py release <version> [--date YYYY-MM-DD]
        Promote `## [Unreleased]` to `## [<version>] - <date>`, open a fresh
        empty `## [Unreleased]` above it, and maintain the link definitions at
        the bottom of the file. Refuses to run when `check` would fail.

    changelog.py notes <version|unreleased>
        Print that section as a `## Highlights` block for the GitHub Release
        body. Deliberately never fails: it runs on the release path, so a
        surprise here must degrade the notes, not break the release. `check`
        is the gate.

`--path` points at a different file, which is how the release-time rewrite is
rehearsed on a copy (see docs/releasing.md).
"""

from __future__ import annotations

import argparse
import datetime
import re
import sys
from pathlib import Path

DEFAULT_PATH = Path("CHANGELOG.md")
FALLBACK_REPO_URL = "https://github.com/shinyaoguri/metaphor"
UNRELEASED = "Unreleased"
NOTES_HEADING = "## Highlights"

# `## [1.2.3] - 2026-08-01`, `## [1.2.3-beta.1] - 2026-08-01`, `## [Unreleased]`
HEADING_RE = re.compile(r"^## \[([^\]]+)\](?:\s+-\s+(\d{4}-\d{2}-\d{2}))?\s*$")
# `[1.2.3]: https://github.com/...` (only ever at the bottom of the file)
LINK_DEF_RE = re.compile(r"^\[([^\]]+)\]:\s*(\S+)\s*$")
COMMENT_RE = re.compile(r"<!--.*?-->", re.DOTALL)
VERSION_RE = re.compile(r"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$")


class ChangelogError(Exception):
    """A problem the maintainer has to fix in CHANGELOG.md."""


class Section:
    def __init__(self, name: str, date: str | None, heading_index: int):
        self.name = name
        self.date = date
        self.heading_index = heading_index
        self.body_end = heading_index + 1  # exclusive; filled in by parse()

    @property
    def body_start(self) -> int:
        return self.heading_index + 1


def parse(lines: list[str]) -> list[Section]:
    """Split the file into `## [...]` sections (in file order)."""
    sections: list[Section] = []
    for i, line in enumerate(lines):
        match = HEADING_RE.match(line)
        if match:
            if sections:
                sections[-1].body_end = i
            sections.append(Section(match.group(1), match.group(2), i))
    if sections:
        sections[-1].body_end = len(lines)
    return sections


def find(sections: list[Section], name: str) -> Section:
    matches = [s for s in sections if s.name.lower() == name.lower()]
    if not matches:
        raise ChangelogError(
            f"no `## [{name}]` section found. "
            "Headings must look like `## [Unreleased]` or `## [1.2.3] - 2026-08-01`."
        )
    if len(matches) > 1:
        raise ChangelogError(
            f"{len(matches)} `## [{name}]` sections found — there must be exactly one."
        )
    return matches[0]


def body_lines(lines: list[str], section: Section) -> list[str]:
    """The section body, minus the trailing link-definition block."""
    return [
        line
        for line in lines[section.body_start : section.body_end]
        if not LINK_DEF_RE.match(line)
    ]


def has_entries(body: list[str]) -> bool:
    """True when the body holds something other than blank lines, HTML
    comments and empty `### Added`-style subheadings."""
    text = COMMENT_RE.sub("", "\n".join(body))
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("###"):
            continue
        return True
    return False


def read(path: Path) -> list[str]:
    try:
        return path.read_text(encoding="utf-8").split("\n")
    except FileNotFoundError:
        raise ChangelogError(f"{path} not found (run from the repository root).")


def repo_url(lines: list[str]) -> str:
    """Derive the repository URL from the existing link definitions so the
    script does not hardcode a second copy of it."""
    for line in lines:
        match = LINK_DEF_RE.match(line)
        if not match:
            continue
        url = match.group(2)
        for marker in ("/compare/", "/releases/tag/"):
            if marker in url:
                return url.split(marker)[0]
    return FALLBACK_REPO_URL


# --------------------------------------------------------------------------
# check
# --------------------------------------------------------------------------
def cmd_check(args: argparse.Namespace) -> int:
    lines = read(args.path)
    sections = parse(lines)
    unreleased = find(sections, UNRELEASED)
    if not has_entries(body_lines(lines, unreleased)):
        raise ChangelogError(
            f"the `## [{UNRELEASED}]` section of {args.path} has no entries.\n"
            "  A release must say what changed. Add the user-facing changes since\n"
            "  the last release under `### Added` / `### Changed` / `### Fixed` /\n"
            "  `### Breaking Changes` etc., then re-run the release.\n"
            "  If a release genuinely carries no user-facing change (a rebuilt\n"
            "  binary asset, say), state that explicitly instead:\n"
            "      ### Changed\n"
            "      - _No user-facing changes._"
        )
    print(f"OK: {args.path} has entries under `## [{UNRELEASED}]`.")
    return 0


# --------------------------------------------------------------------------
# release
# --------------------------------------------------------------------------
def cmd_release(args: argparse.Namespace) -> int:
    version = args.version.lstrip("v")
    if not VERSION_RE.match(version):
        raise ChangelogError(f"'{args.version}' is not a SemVer version (expected e.g. 1.2.3).")
    date = args.date or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    if not re.match(r"^\d{4}-\d{2}-\d{2}$", date):
        raise ChangelogError(f"--date must be YYYY-MM-DD (got '{date}').")

    lines = read(args.path)
    sections = parse(lines)
    if any(s.name == version for s in sections):
        raise ChangelogError(
            f"{args.path} already has a `## [{version}]` section — refusing to promote twice."
        )
    unreleased = find(sections, UNRELEASED)
    if not has_entries(body_lines(lines, unreleased)):
        raise ChangelogError(
            f"the `## [{UNRELEASED}]` section of {args.path} has no entries — "
            "nothing to promote (run `changelog.py check` for the full message)."
        )

    previous = next((s.name for s in sections if s.name != UNRELEASED), None)

    # Promote the heading in place and open a fresh Unreleased above it.
    lines[unreleased.heading_index] = f"## [{version}] - {date}"
    lines[unreleased.heading_index : unreleased.heading_index] = [
        f"## [{UNRELEASED}]",
        "",
    ]

    base = repo_url(lines)
    new_link = (
        f"[{version}]: {base}/compare/v{previous}...v{version}"
        if previous
        else f"[{version}]: {base}/releases/tag/v{version}"
    )
    for i, line in enumerate(lines):
        match = LINK_DEF_RE.match(line)
        if match and match.group(1).lower() == UNRELEASED.lower():
            lines[i] = f"[{UNRELEASED}]: {base}/compare/v{version}...HEAD"
            lines.insert(i + 1, new_link)
            break
    else:
        print(
            f"warning: no `[{UNRELEASED}]:` link definition in {args.path} — "
            "skipped link maintenance.",
            file=sys.stderr,
        )

    args.path.write_text("\n".join(lines), encoding="utf-8")
    print(f"Promoted `## [{UNRELEASED}]` to `## [{version}] - {date}` in {args.path}.")
    return 0


# --------------------------------------------------------------------------
# notes
# --------------------------------------------------------------------------
def cmd_notes(args: argparse.Namespace) -> int:
    """Print a section as a release-notes block. Never fails the release."""
    try:
        lines = read(args.path)
        section = find(parse(lines), args.section)
    except ChangelogError as error:
        print(f"warning: no release highlights emitted — {error}", file=sys.stderr)
        return 0

    body = body_lines(lines, section)
    if not has_entries(body):
        print(
            f"warning: `## [{section.name}]` has no entries — no highlights emitted.",
            file=sys.stderr,
        )
        return 0

    text = COMMENT_RE.sub("", "\n".join(body)).strip("\n")
    print(f"{NOTES_HEADING}\n\n{text}\n")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument(
        "--path",
        type=Path,
        default=DEFAULT_PATH,
        help="changelog file to operate on (default: CHANGELOG.md)",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("check", help="fail when [Unreleased] is missing or empty")

    release = sub.add_parser("release", help="promote [Unreleased] to a version section")
    release.add_argument("version", help="version being released, e.g. 0.8.1")
    release.add_argument("--date", help="release date (default: today, UTC)")

    notes = sub.add_parser("notes", help="print a section as GitHub Release highlights")
    notes.add_argument("section", help="version or 'unreleased'")

    args = parser.parse_args(argv)
    handlers = {"check": cmd_check, "release": cmd_release, "notes": cmd_notes}
    try:
        return handlers[args.command](args)
    except ChangelogError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
