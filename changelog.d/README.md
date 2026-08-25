# changelog.d

One file per user-facing change. At release time `scripts/changelog.py` folds
every file in this directory into `## [Unreleased]` in
[`CHANGELOG.md`](../CHANGELOG.md), then deletes them.

Why not edit `CHANGELOG.md` directly? Because every pull request would append to
the same few lines, and concurrent pull requests then conflict with each other
every single time. A new file conflicts with nothing.

## Adding an entry

Create `changelog.d/<slug>.<category>.md`:

- **`<slug>`** — the pull request or issue number (`382`), or a short
  kebab-case description (`frame-rate-clamp`). It only has to be unique; it
  never appears in the changelog.
- **`<category>`** — one of `breaking`, `added`, `changed`, `deprecated`,
  `removed`, `fixed`, `security`. It selects the subheading the entry lands
  under (`breaking` → `### Breaking Changes`, the rest → `### Added` and
  friends).

The file content is the entry itself: a Markdown list item, in English, written
for someone upgrading the library — what changed, and what they have to do about
it. Link the pull request or issue. Several lines are fine (indented
sub-bullets, a migration table); a leading `- ` is added if you forget it.

Example — `changelog.d/382.fixed.md`:

```markdown
- `frameRate(fps)` now actually clamps the frame rate: the value was stored but
  never applied to `targetFPS` / `preferredFramesPerSecond`
  ([#382](https://github.com/shinyaoguri/metaphor/issues/382))
```

One change per file. A pull request with a breaking change *and* a new API adds
two files.

**Internal-only work needs no entry** — design docs, CI plumbing, refactors with
no observable effect, website dependency bumps. Those pull requests are normally
titled `chore` / `ci` / `docs` / `refactor` / `test`, which the check below
leaves alone.

## Link with absolute URLs, always

**Every link in an entry must be a full `https://` URL** — never `../docs/x`,
never `./x`, never a bare `docs/x`, and never a `#heading` anchor.

The reason is that *an entry body is never rendered next to the entry file*. It
is rendered in two other places, and neither one resolves a target from this
directory:

- `collect` folds the text into [`CHANGELOG.md`](../CHANGELOG.md), which sits at
  the repository root — so `../docs/x` written here points outside the
  repository once it lands there
- `notes` copies the same text into the GitHub Release body, which is served
  from `releases/tag/<version>` — and **a Release body cannot be corrected after
  the release is cut**

That second one is why this is a rule and not a review nit. Twelve such links
were folded into `CHANGELOG.md` before anyone noticed (Issues #1151 / #1181);
the copies in the v0.10.0 Release body are there for good.

Write file targets as `blob/main/…` and directory targets as `tree/main/…`:

```markdown
- Tutorial sketches now live in
  [`docs/tutorial/`](https://github.com/shinyaoguri/metaphor/tree/main/docs/tutorial/),
  and [ADR-0010](https://github.com/shinyaoguri/metaphor/blob/main/docs/adr/0010-tutorial-images-via-gyazo.md)
  records why ([#511](https://github.com/shinyaoguri/metaphor/issues/511)).
```

`changelog.py lint` enforces this on your pull request, so a slip is caught by
the person who can still fix it. To *mention* a path without linking it, put it
in a code span (`` `docs/tutorial/` ``) — code spans and fenced blocks are not
scanned. This file is not an entry, so its own relative links are fine.

## Write links inline, never in reference style

The same rule has a second half. **Write `[text](url)`, never `[text][id]`** —
and never a `[id]: <url>` definition line in an entry:

```markdown
- Tutorials now ship as runnable sketches ([#511][issue]).

[issue]: https://github.com/shinyaoguri/metaphor/issues/511
```

The target is a perfectly good absolute URL, so the rule above is satisfied. It
breaks anyway, because **a reference link needs its definition line, and an
entry has nowhere to keep one** (Issue #1184):

- **Left here**, `collect` folds the definition *inside* `## [Unreleased]`,
  where it is no longer a link definition. `notes` strips that line out of the
  GitHub Release body, so `[#511][issue]` ships as bare text — uncorrectable
  once the release is cut. Worse, the *next* release's `collect` refuses to
  fold around the stray line and stops the release train until someone moves
  it back by hand.
- **Parked at the bottom of [`CHANGELOG.md`](../CHANGELOG.md)** instead, it is
  out of reach of `notes`, which copies one section rather than the whole file.
  The Release body shows the bare text again.

There is no third place. Write the link inline, which is what every entry here
already does:

```markdown
- Tutorials now ship as runnable sketches
  ([#511](https://github.com/shinyaoguri/metaphor/issues/511)).
```

`changelog.py lint` rejects both halves — the `[text][id]` and the definition
line — because rejecting only the definition would let you "fix" it by deleting
that line and shipping the bare text. To *show* the reference syntax without
using it, put it in a code span or a fenced block.

The same check reads `## [Unreleased]` in `CHANGELOG.md`, for the case that
skips this directory entirely: if you write into that section by hand (see the
escape hatch at the end of this file), a link definition left inside it stops
the next `collect` exactly the same way.

## What CI checks on your pull request

Two steps of the required `build-and-test` job look at this directory.

**`changelog.py lint`** validates the files that are here: the name has to be
`<slug>.<category>.md` with a known category, the file must not be empty, and
every link in it has to be an absolute URL written inline (both sections above).
It also checks that `## [Unreleased]` in `CHANGELOG.md` holds no link
definitions. It never asks whether an entry exists.

**`require-changelog-entry.py`** asks that separate question, using the rule the
weekly release train already applies: when the pull request title is a type that
releases on its own (`feat`, `fix`, `perf`) or is marked breaking (`!`), the pull
request has to add a file here. The releasing types are imported from
`release-bump.py` rather than listed again, so the two can never disagree.

This used to be a release-time check only, which meant a forgotten entry was
found on a Monday by a train that could not leave — a week after the person who
could fix it had moved on (Issue #461).

**The judgement call is still yours.** If a `feat` or `fix` genuinely has nothing
an upgrader needs told, label the pull request `no-changelog` and the check
passes; the decision is then recorded on the pull request instead of nowhere.
Either fix takes effect on a re-run alone (`gh run rerun --failed <run-id>`) —
the title and labels are read live from the API, so no push is needed.

Run both locally:

```bash
python3 scripts/changelog.py lint
git diff --name-only --diff-filter=A origin/main... \
    | python3 scripts/require-changelog-entry.py --subject "<your PR title>"
```

## What happens at release

`.github/workflows/release.yml` runs `changelog.py check` at the very start of
the release job, which fails when this directory is empty *and* `## [Unreleased]`
is empty (a release has to be able to say what changed), and when a file here
is malformed — the same well-formedness rules `lint` applies per pull request,
re-checked at the last moment an entry can still be edited. The stable-release path then runs `changelog.py release`,
which collects these files, promotes `## [Unreleased]` to the released version,
and includes the deletions in the release commit.

Order is deterministic: categories in the order listed above, files sorted by
name within a category.

Preview the result without touching the repository:

```bash
rm -rf /tmp/sim && mkdir /tmp/sim
cp -R CHANGELOG.md changelog.d /tmp/sim/
python3 scripts/changelog.py --path /tmp/sim/CHANGELOG.md --dir /tmp/sim/changelog.d collect
```

Writing directly under `## [Unreleased]` in `CHANGELOG.md` still works, and is
the right escape hatch for a hotfix released from a branch where this directory
has already been drained. Both are accepted by `check`, `collect` and `notes` —
subject to the same link rules, since the text ends up in the same two places.
Keep the link definitions in the block at the bottom of the file, below the last
version section; one left inside `## [Unreleased]` stops the next `collect`.

See [CONTRIBUTING.md](../CONTRIBUTING.md) and [docs/releasing.md](../docs/releasing.md).
