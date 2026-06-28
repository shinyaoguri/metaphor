# Releasing (metaphor & metaphor-cli)

How releases are cut for **metaphor** (this repo) and the downstream
**metaphor-cli**. The summary lives in [CLAUDE.md](../CLAUDE.md) under *Branching
Workflow*; this file is the full procedure.

## Mechanism

Releases go through a single `workflow_dispatch` trigger on the **Release**
workflow. No PAT required — the workflow re-enters CI on its own release branch
using `workflow_dispatch` (which is exempt from the `GITHUB_TOKEN` recursion
guard).

## Label-driven releases (the normal path)

Releases are cut by **labeling a PR**, not by a separate branch:

1. On the PR you want to ship, add one label: `release:patch` / `release:minor`
   / `release:major`.
2. Merge it (squash). `release-on-merge.yml` reads the label and dispatches the
   **Release** workflow with that bump, which builds, bumps versions, tags, and
   publishes:
   - **metaphor** → git tag + GitHub Release (SPM) + Syphon-pin dispatch to metaphor-cli.
   - **metaphor-cli** → tarballs + Homebrew formula pushed to `shinyaoguri/homebrew-tap`.
3. A PR **without** a `release:*` label merges normally and does **not** release.
   (The Release workflow's own "Release vX.Y.Z" PR is unlabeled, so it never
   re-triggers a release — no loop.)

Pre-releases (beta/rc) are cut manually via the Release workflow's
`workflow_dispatch` (`bump=prerelease` etc.).

## Manual dispatch inputs

| Input | Purpose |
|-------|---------|
| `bump` | `patch` / `minor` / `major` / `prerelease` |
| `prerelease_label` | `beta`, `rc`, etc. Empty for stable. Ignored when `bump=prerelease`. |

## Common operations

| Goal | Inputs | Resulting tag |
|------|--------|---------------|
| Stable patch | `bump=patch`, label empty | `v0.2.4` |
| Start a beta cycle | `bump=minor`, `label=beta` | `v0.3.0-beta.1` |
| Iterate the beta | `bump=prerelease` | `v0.3.0-beta.2` |
| Promote to RC | `bump=minor`, `label=rc` | `v0.3.0-rc.1` |
| Graduate to stable | `bump=minor`, label empty | `v0.3.0` |

Pre-release tags (anything containing `-`) are automatically marked as
Pre-release on GitHub. The `Package.swift` `from:` example in the README is only
updated for stable releases.
