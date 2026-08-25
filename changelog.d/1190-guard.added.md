- Two test suites now guard the licensing of everything checked in under `Examples/`
  ([#1190](https://github.com/shinyaoguri/metaphor/issues/1190)). One fails outright if any
  redistributed file declares GPL, LGPL or a Creative Commons NonCommercial license — the
  category that had to be removed in the first place — and it takes no allowlist, because
  the only fix for such a file is to take it out. The other pins the counts recorded in
  `THIRD_PARTY_LICENSES.md` (how many Processing `.pde` and `.json` originals ship, and how
  many of them carry a credit line) against the tree, so adding or removing samples, or a
  credited author the notice has never named, turns the suite red instead of drifting
  silently. Nothing to do when upgrading — these run in `make test`.
