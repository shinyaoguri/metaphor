# API Stability Policy

What `metaphor` promises not to break, and what it does not promise at all.

**Status.** The library is currently `0.9.x`. This policy has been **in effect
since `v0.9.0`** (released 2026-08-10), the API-freeze release: breaking a
public API now requires a major release. `v1.0.0` will declare the same
contract formally. See
[docs/design/v1-release-plan.md](design/v1-release-plan.md) for the milestones.

`metaphor` follows [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).
Every user-visible change is recorded in [CHANGELOG.md](../CHANGELOG.md), with
breaking ones under a `### Breaking Changes` heading.

## 1. What is public API

The library is layered. Everything a release advertises as a
[library product](../Package.swift) is covered:

| Layer | Examples | Covered? |
|---|---|---|
| **Sketch layer** — the `Sketch` protocol and its extensions | `circle`, `fill`, `box`, `beginFrameRecord` | **Yes.** This is the canonical documented surface (ADR-0005 Decision 3) |
| **`SketchContext`** — the bridge from `Sketch` to the canvases | `SketchContext.screenPosition`, plugin-facing hooks | **Yes** |
| **Canvas / module layer** — `Canvas2D`, `Canvas3D`, `MetaphorRenderer`, and the 12 module libraries (`MetaphorAudio`, `MetaphorPhysics`, `MetaphorRenderGraph`, …) | `Canvas3D.draw(_:)`, `AudioAnalyzer.init`, `MetaphorError` | **Yes** |
| **Internal implementation** | encoders, batchers, shader plumbing | No |

**The access modifier is the promise.** If a symbol is reachable from a library
product, it is covered; if it is `internal`, it is not. That was not true when
this document was first written — a handful of symbols documented themselves as
internal while being declared `public` — so
[#388](https://github.com/shinyaoguri/metaphor/issues/388) moved every one of
them to `internal` before the freeze (ADR-0007 Decision 6). There is no longer a
category of "public but not really", and no `@_spi` is in use: the five affected
symbols (`MetaphorRenderer.onCaptureOutput` / `.shadowDeferActive` /
`.onRecordFrame` / `.onReplayMain`, and `MetaphorSyphon.SyphonPlugin`) turned
out to be needed only inside their own module and from `@testable` tests, so
plain `internal` was enough. Underscore-prefixed `public` symbols are gone too —
`_metaphorSyphonRegister()` was the last one.

Still explicitly **not** public API:

- Anything imported through `@_spi(...)`, should the library ever introduce it.
  SPI is unversioned and may change in any release, including a patch. **Nothing
  uses `@_spi` today**, and adding it means recording the reason here.
- `MetaphorTestSupport` — a target, not a library product, so no package can
  depend on it.
- `Examples/` (278 standalone packages), the DocC catalog, and the generated
  files (`llms.txt`, `llms-sketch.txt`, `docs/ai/examples-index.*`,
  `Sources/MetaphorCore/Shaders/ShaderSources/*.txt`). `llms.txt` mirrors the
  public API surface but is a derived artifact and carries no separate promise.

## 2. Source compatibility only — no ABI stability

`metaphor` ships as SwiftPM source and is compiled by each consumer, so there is
no binary interface to keep stable: **no `library-evolution` mode, no
`@frozen`, no ABI guarantee.** The promise is that code which compiled against
`X.Y.Z` still compiles against `X.Y+1.0`.

Source compatibility has consequences that a "we only added things" mindset
misses. These count as breaking:

- Adding a case to a public `enum` (it breaks exhaustive `switch`) — this is why
  the error-type unification in [#323](https://github.com/shinyaoguri/metaphor/issues/323)
  is listed as a breaking change.
- Adding a protocol requirement without a default implementation.
- Adding an overload that makes an existing call site ambiguous.

## 3. Deprecation

Nothing is removed without a warning period, and **the unit of that period is a
published release** — not a pull request, not a phase (ADR-0005 Amendment
2026-07-03, written after a deprecation and its removal shipped in the same
release):

- A symbol is marked `@available(*, deprecated, message:)` with the replacement
  named in the message, and that state must appear in a **published minor
  release**.
- Removal happens no earlier than the following minor (through `0.9.x`), and
  after `1.0.0` requires a **major** release.
- Deprecations and removals both get CHANGELOG entries with a migration table.

## 4. Where each kind of change lands

SemVer's `major` is about **source compatibility**. Runtime contracts (Probe
files, stdin, environment variables) and rendering output carry their own
versioning and coordination rules, described below; they never force a library
major on their own.

| Change | Bump |
|---|---|
| Removing, renaming, or source-incompatibly changing public API (§2) | **major** |
| Adding public API | minor |
| Deprecating public API | minor |
| Bug fix with no API change | patch |
| Raising the minimum macOS / Swift version (§7) | minor (never patch) |
| Deliberate change to rendering output for an unchanged sketch (§5) | minor (never patch) |
| Breaking change to a runtime contract — Probe wire schema, stdin protocol, contract environment variables (§6) | minor (never patch), plus the CONTRACT.md procedure |
| Additive change to a runtime contract | minor |
| Anything under "not public API" (§1) | any release, including patch |

Everything in the "minor (never patch)" rows also gets a `### Breaking Changes`
CHANGELOG entry, so upgraders see it whether or not the major digit moved.

## 5. Rendering output

Rendering output is not part of the source-compatibility promise — pixels do not
break compilation — but it is what a sketch author actually notices, so it gets
the same disclosure treatment.

- A golden-image suite (`Tests/metaphorTests/Golden/`) pins representative
  scenes: 2D shapes, blend modes, Blinn-Phong and PBR lighting, shadow casting,
  post-processing, and 2D transforms applied to 3D. It is **representative, not
  exhaustive** — it makes visual regressions visible in review, it does not
  enumerate the promise.
- Fixing a rendering bug (the output was wrong) is a normal fix and can ship in
  a patch.
- Deliberately changing the output of a correct sketch ships in a minor at the
  earliest, with a `### Breaking Changes` entry explaining what to do — as the
  `P3D` transform unification did ([#325](https://github.com/shinyaoguri/metaphor/issues/325)).
  This stays possible after 1.0: ADR-0003 Amendment 2026-08-02 keeps the option
  of turning command recording on by default open on exactly those terms.

## 6. Runtime contracts, and what is *not* one

Some of what `metaphor` exposes is not Swift API at all. The
[CONTRACT.md](../CONTRACT.md) subset is jointly owned with
[`metaphor-cli`](https://github.com/shinyaoguri/metaphor-cli) and can only be
changed by a coordinated pair of pull requests:

| Surface | Rule |
|---|---|
| **Probe wire schema** (`frame.json` / `sequence.json` / `request.json`) | Additive and forward-compatible by default; consumers ignore unknown keys. A rename, removal, or type change bumps `schemaVersion` (currently `frame.json` = 4) and requires the cross-repo procedure. The machine-readable source of truth is `contract/*.schema.json` (ADR-0004) |
| **stdin JSON Lines input** (`t` = `mouseDown`, `keyDown`, …) | Adding an event type or field is additive. The protocol has **no version number yet** and no stated rule for unknown `t` values — being defined in [#339](https://github.com/shinyaoguri/metaphor/issues/339) as part of the 1.0 freeze point |
| **Contract environment variables** (`METAPHOR_VIEWER`, `METAPHOR_SYPHON_NAME`, `METAPHOR_FPS`, `METAPHOR_PROBE`, `METAPHOR_SOURCE_STAMP`) | Renaming, removing, or changing the meaning of one is a breaking runtime change and needs the matching `metaphor-cli` change in the same wave |

**Not every supported switch is a contract.** `METAPHOR_COMMAND_RECORD` is the
worked example: ADR-0003 Amendment 2026-08-02 keeps it as an official opt-in
past 1.0, and it is documented in [DEVELOPMENT.md](../DEVELOPMENT.md) — but it
is deliberately **excluded from CONTRACT.md**, because `metaphor-cli` never sets
it and it is not a coupling point between the repositories. So it is covered by
this policy (removing it would be a documented breaking change) and not by the
cross-repo procedure. Environment variables that appear in neither CONTRACT.md
nor DEVELOPMENT.md — test and build switches such as `METAPHOR_REQUIRE_GPU` or
`METAPHOR_UPDATE_GOLDEN` — carry no promise at all.

## 7. Supported platforms and toolchains

- **macOS 14.0+, Apple Silicon only.** There is no Intel code path.
- **Swift 5.10 / Xcode 15.4 minimum.** The required CI check `build-swift-5-10`
  builds against that toolchain on every pull request, so a newer-SDK symbol
  cannot land unnoticed. This minimum is why typed throws (SE-0413, Swift 6.0)
  is deferred rather than adopted — ADR-0005 Amendment 2026-08-02.
- Raising either minimum ships in a **minor** release (never a patch), announced
  in the CHANGELOG and the release notes. The expected trigger is losing the
  ability to verify: when GitHub Actions retires the `macos-14` runner, the
  minimum is reconsidered rather than silently unverified. Users who cannot move
  stay on the last release that supported them by pinning an upper bound.

## 8. `@_exported import` is frozen

`MetaphorCore` re-exports **`Metal`, `MetalKit`, and `simd`** into the importer's
namespace. This is intentional and part of the frozen surface (ADR-0007 Decision
5): the public API itself exposes ~120 declarations mentioning `MTL*` types and
~25 mentioning `simd`-specific types, so `import metaphor` alone has to be enough
to name the types in a signature you can already see. Removing any of the three
would be a major change. The trade-off accepted with it: `simd`'s global
functions (`dot`, `cross`, `normalize`, …) live in your namespace too, and
`@_exported` is an unofficial attribute whose removal by a future Swift would be
handled in a major release.

## 9. The `0.9.x` discipline

`0.9.x` is the freeze rehearsal, run under exactly these rules:

- **Additive changes and fixes only.** Anything breaking that becomes necessary
  is a signal that the freeze was premature, not a routine exception — it gets
  discussed as such before it is merged.
- All 13 modules are treated as frozen for the whole `0.9` series. `v1.0.0` is
  the last `0.9.x` promoted essentially unchanged.
- **Preview (unstable) modules.** If a module turns out to need breaking changes
  during `0.9.x`, it is not force-frozen: it is declared **preview** at 1.0. A
  preview module is listed as such in a table in this document, says so in the
  first line of its own module documentation, and may take breaking changes in a
  minor release with a CHANGELOG entry. **No module is preview today** — the
  line is drawn from the `0.9.x` record, not from speculation.

## 10. Maintenance expectations

`metaphor` is maintained by one person on a best-effort basis (see the READMEs
and [SECURITY.md](../SECURITY.md)). Concretely: releases are automated and
require no privileged human step, issues and security reports are acknowledged
within a few days, and only the latest published release receives fixes — there
are no backport branches. The promises in this document are about **what will
not silently break**, not about response times.

## References

- [ADR-0005](adr/0005-sketch-api-consistency.md) — Sketch-layer conventions, the
  deprecation window, error reporting, deferred typed throws, `P3D` semantics
- [ADR-0007](adr/0007-finalize-public-api-surface.md) — the two-layer naming
  principle, recording-API naming, `@_exported`, hiding internal `public` surface
- [ADR-0003](adr/0003-unified-command-stream.md) — command recording and
  `METAPHOR_COMMAND_RECORD`
- [ADR-0004](adr/0004-wire-schema-canon-vs-shared-types.md) — the wire schema as
  the source of truth for the Probe contract
- [CONTRACT.md](../CONTRACT.md) — the `metaphor` ⇄ `metaphor-cli` runtime contract
- [CHANGELOG.md](../CHANGELOG.md) · [docs/releasing.md](releasing.md) ·
  [CONTRIBUTING.md](../CONTRIBUTING.md)
