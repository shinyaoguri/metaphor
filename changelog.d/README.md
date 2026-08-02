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
no observable effect, website dependency bumps.

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
