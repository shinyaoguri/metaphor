#!/usr/bin/env python3
"""Keep a Changelog helper for CHANGELOG.md.

Entries are written one-per-file into `changelog.d/` (see changelog.d/README.md)
so that concurrent pull requests never touch the same lines of CHANGELOG.md.
They are folded into `## [Unreleased]` at release time, not at merge time.

Four subcommands, all but `collect` driven by .github/workflows/release.yml:

    changelog.py check
        Fail when there is nothing to release: no entry files in `changelog.d/`
        AND an empty (or missing, or duplicated) `## [Unreleased]` section. Also
        rejects malformed entry filenames, so a typo is caught here rather than
        at collect time. Runs at the very start of the release job, before
        anything irreversible (branch push, tag, GitHub Release) has happened.

    changelog.py collect
        Fold `changelog.d/*.md` into `## [Unreleased]`, grouped under the usual
        `### Added` / `### Fixed` / ... subheadings, then delete the collected
        files. Deterministic: categories in a fixed order, files sorted by name
        within a category. `release` runs this first, so it is normally only
        invoked by hand to preview the result.

    changelog.py release <version> [--date YYYY-MM-DD]
        `collect`, then promote `## [Unreleased]` to `## [<version>] - <date>`,
        open a fresh empty `## [Unreleased]` above it, and maintain the link
        definitions at the bottom of the file. Refuses to run when `check`
        would fail.

    changelog.py notes <version|unreleased>
        Print that section as a `## Highlights` block for the GitHub Release
        body. `unreleased` also folds in the pending `changelog.d/` entries, so
        a prerelease previews everything queued. Deliberately never fails: it
        runs on the release path, so a surprise here must degrade the notes,
        not break the release. `check` is the gate.

`--path` points at a different changelog file and `--dir` at a different entry
directory, which is how the release-time rewrite is rehearsed on a copy (see
docs/releasing.md).
"""

from __future__ import annotations

import argparse
import datetime
import re
import sys
from pathlib import Path

DEFAULT_PATH = Path("CHANGELOG.md")
DEFAULT_DIR = Path("changelog.d")
FALLBACK_REPO_URL = "https://github.com/shinyaoguri/metaphor"
UNRELEASED = "Unreleased"
NOTES_HEADING = "## Highlights"

# `<slug>.<category>.md` — the category segment picks the subheading below.
# Order matters: it is the order the subsections are emitted in (Keep a
# Changelog's order, with Breaking Changes hoisted to the top so upgraders see
# it first — the same deliberate extension CHANGELOG.md documents).
CATEGORIES: list[tuple[str, str]] = [
    ("breaking", "Breaking Changes"),
    ("added", "Added"),
    ("changed", "Changed"),
    ("deprecated", "Deprecated"),
    ("removed", "Removed"),
    ("fixed", "Fixed"),
    ("security", "Security"),
]
CATEGORY_HEADINGS = dict(CATEGORIES)
CATEGORY_ORDER = {name: i for i, (name, _) in enumerate(CATEGORIES)}
# Files in changelog.d/ that are documentation, not entries.
NOT_AN_ENTRY = {"README.md"}
SLUG_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")

# `## [1.2.3] - 2026-08-01`, `## [1.2.3-beta.1] - 2026-08-01`, `## [Unreleased]`
HEADING_RE = re.compile(r"^## \[([^\]]+)\](?:\s+-\s+(\d{4}-\d{2}-\d{2}))?\s*$")
SUBHEADING_RE = re.compile(r"^### +(.+?)\s*$")
# `[1.2.3]: https://github.com/...` (only ever at the bottom of the file)
LINK_DEF_RE = re.compile(r"^\[([^\]]+)\]:\s*(\S+)\s*$")
COMMENT_RE = re.compile(r"<!--.*?-->", re.DOTALL)
LIST_ITEM_RE = re.compile(r"^\s*(?:[-*+]\s|\d+\.\s)")
VERSION_RE = re.compile(r"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$")


class ChangelogError(Exception):
    """A problem the maintainer has to fix in CHANGELOG.md or changelog.d/."""


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
# changelog.d/ entry files
# --------------------------------------------------------------------------
class Fragment:
    """One `changelog.d/<slug>.<category>.md` file."""

    def __init__(self, path: Path, category: str):
        self.path = path
        self.category = category

    @property
    def heading(self) -> str:
        return CATEGORY_HEADINGS[self.category]

    def lines(self) -> list[str]:
        """The entry as it should appear under its subheading."""
        text = self.path.read_text(encoding="utf-8")
        body = [line.rstrip() for line in text.split("\n")]
        while body and not body[0].strip():
            body.pop(0)
        while body and not body[-1].strip():
            body.pop()
        if not body:
            raise ChangelogError(f"{self.path} is empty — write the entry or delete the file.")
        # Entries are Markdown list items. Accept a bare sentence too rather
        # than failing a release over a missing dash. `**bold**` at the start of
        # a line is not a bullet, hence the required space in LIST_ITEM_RE.
        if not LIST_ITEM_RE.match(body[0]):
            body[0] = f"- {body[0].lstrip()}"
        return body


def fragments(directory: Path) -> list[Fragment]:
    """Every entry file, in emission order (category, then filename).

    Raises rather than skipping on anything unrecognised: a misnamed file that
    is silently ignored is an entry that silently never ships.
    """
    if not directory.is_dir():
        return []
    found: list[Fragment] = []
    for path in sorted(directory.iterdir(), key=lambda p: p.name):
        if path.name.startswith(".") or not path.is_file():
            continue
        if path.name in NOT_AN_ENTRY:
            continue
        stem, dot, suffix = path.name.rpartition(".")
        if not dot or suffix != "md":
            raise ChangelogError(
                f"{path} is not a changelog entry. Entry files are named "
                "`<slug>.<category>.md` (see changelog.d/README.md); move "
                "anything else elsewhere."
            )
        slug, dot, category = stem.rpartition(".")
        if not dot or not SLUG_RE.match(slug):
            raise ChangelogError(
                f"{path} is missing the category segment. Name entries "
                "`<slug>.<category>.md`, e.g. `382.breaking.md` or "
                f"`frame-rate-clamp.fixed.md`. Categories: {', '.join(CATEGORY_HEADINGS)}."
            )
        if category not in CATEGORY_HEADINGS:
            raise ChangelogError(
                f"{path} has an unknown category '{category}'. "
                f"Use one of: {', '.join(CATEGORY_HEADINGS)}."
            )
        found.append(Fragment(path, category))
    found.sort(key=lambda f: (CATEGORY_ORDER[f.category], f.path.name))
    return found


def split_subsections(body: list[str]) -> tuple[list[str], list[tuple[str, list[str]]]]:
    """Split a section body into (preamble, [(subheading, lines), ...])."""
    preamble: list[str] = []
    subsections: list[tuple[str, list[str]]] = []
    current: list[str] | None = None
    for line in body:
        match = SUBHEADING_RE.match(line)
        if match:
            current = []
            subsections.append((match.group(1), current))
            continue
        (preamble if current is None else current).append(line)
    return preamble, subsections


def trim(lines: list[str]) -> list[str]:
    out = list(lines)
    while out and not out[0].strip():
        out.pop(0)
    while out and not out[-1].strip():
        out.pop()
    return out


def merge_body(body: list[str], entries: list[Fragment]) -> list[str]:
    """Fold `entries` into a section body, emitting subsections in category
    order. Content that is already there is preserved verbatim; unknown
    subheadings are kept (after the known ones) rather than dropped."""
    preamble, subsections = split_subsections(body)
    merged: dict[str, list[str]] = {}
    order: list[str] = []
    for heading, lines in subsections:
        key = heading.lower()
        if key in merged:
            merged[key].extend([""] + trim(lines))
        else:
            merged[key] = trim(lines)
            order.append(heading)

    for fragment in entries:
        key = fragment.heading.lower()
        if key not in merged:
            merged[key] = []
            order.append(fragment.heading)
        if merged[key]:
            merged[key].extend(fragment.lines())
        else:
            merged[key] = fragment.lines()

    known = {heading.lower(): i for i, (_, heading) in enumerate(CATEGORIES)}
    seen = {heading: i for i, heading in enumerate(order)}
    order.sort(key=lambda h: (known.get(h.lower(), len(CATEGORIES)), seen[h]))

    out: list[str] = [""]
    preamble = trim(preamble)
    if preamble:
        out += preamble + [""]
    for heading in order:
        out += [f"### {heading}", ""] + merged[heading.lower()] + [""]
    return out


# --------------------------------------------------------------------------
# check
# --------------------------------------------------------------------------
def cmd_check(args: argparse.Namespace) -> int:
    pending = fragments(args.dir)
    for fragment in pending:
        fragment.lines()  # rejects an empty entry file here, not at collect time
    lines = read(args.path)
    unreleased = find(parse(lines), UNRELEASED)
    if not pending and not has_entries(body_lines(lines, unreleased)):
        raise ChangelogError(
            f"nothing to release: {args.dir}/ has no entry files and the "
            f"`## [{UNRELEASED}]` section of {args.path} is empty.\n"
            "  A release must say what changed. Add one file per change to\n"
            f"  {args.dir}/, named `<slug>.<category>.md` "
            f"({', '.join(CATEGORY_HEADINGS)}) —\n"
            "  see changelog.d/README.md — then re-run the release.\n"
            "  If a release genuinely carries no user-facing change (a rebuilt\n"
            "  binary asset, say), state that explicitly instead, e.g. a file\n"
            "  `no-user-facing-changes.changed.md` containing:\n"
            "      - _No user-facing changes._"
        )
    if pending:
        print(f"OK: {len(pending)} entr{'y' if len(pending) == 1 else 'ies'} in {args.dir}/.")
    else:
        print(f"OK: {args.path} has entries under `## [{UNRELEASED}]`.")
    return 0


# --------------------------------------------------------------------------
# collect
# --------------------------------------------------------------------------
def collect(args: argparse.Namespace) -> list[Fragment]:
    """Fold changelog.d/ into `## [Unreleased]` and delete what was folded."""
    pending = fragments(args.dir)
    if not pending:
        return []
    lines = read(args.path)
    unreleased = find(parse(lines), UNRELEASED)
    if any(LINK_DEF_RE.match(line) for line in lines[unreleased.body_start : unreleased.body_end]):
        raise ChangelogError(
            f"link definitions found inside the `## [{UNRELEASED}]` section of "
            f"{args.path} — they belong at the bottom of the file."
        )
    lines[unreleased.body_start : unreleased.body_end] = merge_body(
        lines[unreleased.body_start : unreleased.body_end], pending
    )
    args.path.write_text("\n".join(lines), encoding="utf-8")
    for fragment in pending:
        fragment.path.unlink()
    return pending


def cmd_collect(args: argparse.Namespace) -> int:
    collected = collect(args)
    if not collected:
        print(f"No entries in {args.dir}/ — {args.path} left unchanged.")
        return 0
    print(
        f"Collected {len(collected)} entr{'y' if len(collected) == 1 else 'ies'} from "
        f"{args.dir}/ into `## [{UNRELEASED}]` of {args.path}:"
    )
    for fragment in collected:
        print(f"  {fragment.path.name} -> ### {fragment.heading}")
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

    # Refuse before touching anything: `collect` writes the file and deletes
    # the entry files, so a version clash has to be caught first.
    if any(s.name == version for s in parse(read(args.path))):
        raise ChangelogError(
            f"{args.path} already has a `## [{version}]` section — refusing to promote twice."
        )

    cmd_collect(args)

    lines = read(args.path)
    sections = parse(lines)
    unreleased = find(sections, UNRELEASED)
    if not has_entries(body_lines(lines, unreleased)):
        raise ChangelogError(
            f"the `## [{UNRELEASED}]` section of {args.path} has no entries and "
            f"{args.dir}/ was empty — nothing to promote "
            "(run `changelog.py check` for the full message)."
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
        body = body_lines(lines, section)
        if section.name.lower() == UNRELEASED.lower():
            # A prerelease does not consume changelog.d/, so preview it here.
            pending = fragments(args.dir)
            if pending:
                body = merge_body(body, pending)
    except ChangelogError as error:
        print(f"warning: no release highlights emitted — {error}", file=sys.stderr)
        return 0

    if not has_entries(body):
        print(
            f"warning: `## [{args.section}]` has no entries — no highlights emitted.",
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
    parser.add_argument(
        "--dir",
        type=Path,
        default=DEFAULT_DIR,
        help="directory of per-change entry files (default: changelog.d)",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("check", help="fail when there is nothing to release")

    sub.add_parser("collect", help="fold changelog.d/ entries into [Unreleased]")

    release = sub.add_parser("release", help="collect, then promote [Unreleased] to a version")
    release.add_argument("version", help="version being released, e.g. 0.8.1")
    release.add_argument("--date", help="release date (default: today, UTC)")

    notes = sub.add_parser("notes", help="print a section as GitHub Release highlights")
    notes.add_argument("section", help="version or 'unreleased'")

    args = parser.parse_args(argv)
    handlers = {
        "check": cmd_check,
        "collect": cmd_collect,
        "release": cmd_release,
        "notes": cmd_notes,
    }
    try:
        return handlers[args.command](args)
    except ChangelogError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
