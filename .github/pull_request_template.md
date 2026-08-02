<!--
This repo merges with squash merge only: your PR title becomes the final
commit message, so write it as a Conventional Commit —
`<type>(<scope>): <summary>` (feat / fix / docs / refactor / test / chore / ci).
See CONTRIBUTING.md for the full guidelines.
-->

## Purpose

<!-- Why is this change needed? Link the Issue it addresses, if any. -->

## Changes

<!-- What did you change, at a level someone skimming the diff would want to know? -->

## How to verify

<!-- Commands you ran (e.g. `make test`), manual steps, or screenshots. -->

<!--
Does this change what gets DRAWN (shaders, lighting, transforms, layout,
golden-image updates, examples' visual output)? Then include before/after
images in this PR. For files committed in this PR (e.g. golden PNGs) embed
them via raw URLs — see DEVELOPMENT.md "PR に見た目の証跡を載せる" for the
one-liner; otherwise attach screenshots (Probe: METAPHOR_PROBE=1 captures
.metaphor/probe/current/frame.png headlessly).
-->

<!--
User-facing change? Add ONE file to changelog.d/ — `<slug>.<category>.md`,
e.g. changelog.d/382.fixed.md (categories: breaking, added, changed,
deprecated, removed, fixed, security). Don't edit CHANGELOG.md directly;
the release workflow collects these files into it. Internal-only changes
don't need an entry. See changelog.d/README.md and CONTRIBUTING.md.
-->

---

Fixes #<!-- issue number, if applicable -->

<!--
Maintainer note: release:patch / release:minor / release:major labels drive
automatic releases on merge — please leave them for maintainers to set.
-->
