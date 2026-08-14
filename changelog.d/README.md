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

## What CI checks on your pull request

Two steps of the required `build-and-test` job look at this directory.

**`changelog.py lint`** validates the files that are here: the name has to be
`<slug>.<category>.md` with a known category, and the file must not be empty. It
never asks whether an entry exists.

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
is empty (a release has to be able to say what changed), and when a filename
here is malformed. The stable-release path then runs `changelog.py release`,
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
has already been drained. Both are accepted by `check`, `collect` and `notes`.

See [CONTRIBUTING.md](../CONTRIBUTING.md) and [docs/releasing.md](../docs/releasing.md).
