# Contributing to metaphor

> 日本語での問い合わせも歓迎です。Issue や PR は日本語・英語どちらで書いても構いません。以下は英語で書かれたコミュニティ標準文書です。

Thanks for your interest in `metaphor`! This project is still evolving, and
reports of any size — from a one-line typo to a design discussion — are
welcome.

## Reporting bugs / requesting features

Please use the [Issue templates](https://github.com/shinyaoguri/metaphor/issues/new/choose):

- **Bug report** — walks you through the environment info, reproduction
  steps, and expected/actual behavior we need to act on a report.
- **Feature request** — motivation, proposal, and alternatives considered.
- **Question** — anything that doesn't fit the above.

If you're not sure whether something belongs in `metaphor` (this library) or
[`metaphor-cli`](https://github.com/shinyaoguri/metaphor-cli) (the `metaphor`
command: `new` / `run` / `watch` / `mcp`, installation, Homebrew), file it
here and we'll route it — the Issue template's contact links also point at
the CLI repo directly.

## Development setup

Full setup, build/test commands, generated-file handling, and the release
process live in [DEVELOPMENT.md](DEVELOPMENT.md) — start there before
sending a PR. The short version:

```bash
git clone --recursive https://github.com/shinyaoguri/metaphor.git
cd metaphor
make setup    # submodules + Syphon.xcframework
make build
make test
make ci-check # before pushing: build + test with CI's -warnings-as-errors
```

Tests use the **Swift Testing** framework (`@Suite` / `@Test`), not XCTest.

`make build` / `make test` stay lenient so you can iterate through warnings,
but CI builds and tests with `-Xswiftc -warnings-as-errors` — run
`make ci-check` before you push so a warning doesn't turn into a red CI on a
green local run ([#448](https://github.com/shinyaoguri/metaphor/issues/448)).

## Sending a pull request

- Branch from `main`. Keep PRs small and focused on one concern; open a
  [Draft PR](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/about-pull-requests#draft-pull-requests)
  early if it's still in progress.
- This repo merges with **squash merge only** — your PR title becomes the
  final commit message, so write it as a
  [Conventional Commit](https://www.conventionalcommits.org/):
  `<type>(<scope>): <summary>` (`feat` / `fix` / `docs` / `refactor` / `test`
  / `chore` / `ci` / `perf`; append `!` for a breaking change). **This is
  enforced** — the *Lint PR title* step of `build-and-test` rejects anything
  else, so a merge is blocked until the title is fixed. Fill in the PR body's
  Purpose / Changes / How to verify sections from
  [`.github/pull_request_template.md`](.github/pull_request_template.md).
- The only required CI check is the aggregate gate `ci-gate`, which fails if
  any upstream job — `build-and-test`, `build-swift-5-10` (the Swift 5.10 /
  Xcode 15.4 minimum toolchain), `website-build` (the Astro landing page), or
  `examples-diff-build` — failed (skipped jobs count as success). PRs are merged with `gh pr merge --squash --auto`;
  a PR touching `Examples/` waits for the changed examples to build (up to
  60 min), other PRs merge as soon as the fast jobs are green (see
  [docs/releasing.md](docs/releasing.md)).
- **If your change is user-facing, add a file to
  [`changelog.d/`](changelog.d/README.md)** — not to `CHANGELOG.md` itself,
  which every pull request would otherwise edit on the same lines. Name it
  `<slug>.<category>.md` (`382.fixed.md`, `frame-rate-clamp.fixed.md`;
  categories `breaking` / `added` / `changed` / `deprecated` / `removed` /
  `fixed` / `security`) and write the entry as a Markdown list item in English.
  Entries are wanted for new or changed API, behavior differences, bug fixes
  people would notice, anything that needs a migration step; breaking ones go
  in a `.breaking.md` file, since they become the 1.0 migration guide.
  Internal-only work — design docs, CI plumbing, refactors with no observable
  effect — doesn't need an entry. The release workflow collects these files
  into `## [Unreleased]` and refuses to cut a release while there is nothing
  to collect, so nothing ships undocumented; see
  [changelog.d/README.md](changelog.d/README.md) and
  [docs/releasing.md](docs/releasing.md) for the mechanics.
- **If your change touches public API, read
  [docs/api-stability-policy.md](docs/api-stability-policy.md) first** — which
  layers are covered, what counts as source-breaking (removing a symbol, but
  also adding an `enum` case or a protocol requirement), and the deprecation
  window: a symbol is marked deprecated in a *published* release before it can
  be removed, never both in one.
- Releases ride a **weekly train** (Mondays, 09:00 JST): whatever is on `main`
  ships together, with the bump derived from the merged PR titles. Nothing to
  do on your side. The `release:now` / `release:patch` / `release:minor` /
  `release:major` labels cut a release immediately instead — they're
  **maintainer-only**; please don't add them to your PR.
- A few files are **generated** and must not be hand-edited — change the
  input and regenerate instead (a pre-push hook and CI both check for
  staleness):

  | Output | Input | Regenerate with |
  |---|---|---|
  | `llms.txt` | `Sources/**/*.swift`, `scripts/generate-llms-txt.py` | `make llms-txt` |
  | `docs/ai/examples-index.{md,json}` | `Examples/**`, `scripts/generate-examples-index.py` | `make examples-index` |
  | `Sources/MetaphorCore/Shaders/ShaderSources/*.txt` | `Shaders/Metal/*.metal`, `scripts/generate-shader-sources.py` | `python3 scripts/generate-shader-sources.py` |
  | Embedded code blocks in `docs/tutorial/*.md` | `Examples/Tutorial/**`, `scripts/generate-tutorial-snippets.py` | `make tutorial-snippets` |

- If your change touches the runtime contract with `metaphor-cli`
  (environment variables, stdin JSON Lines, Probe files, Syphon version pin),
  see [CONTRACT.md](CONTRACT.md) — it needs a matching PR in that repo too,
  and `./scripts/check-contract.sh` should stay green.
- New tests should fail first against the old behavior (for bug fixes) or be
  seen to fail before the feature lands, then pass once the change is in.
- If you notice something unrelated to your change while working (a bug, a
  doc gap, an idea), please open a separate Issue for it instead of folding
  it into the same PR.

## Code of conduct

Be respectful and assume good faith. There's no separate `CODE_OF_CONDUCT.md`
yet — treat this project like any other collaborative open-source space.

## License

By contributing, you agree that your contributions will be licensed under
the project's [MIT License](LICENSE).
