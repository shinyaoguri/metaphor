# Changelog

All notable changes to `metaphor` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
with the usual `0.x` caveat: **while the major version is 0, a minor release may
break API**. Those breaks are always listed under a **Breaking Changes** heading
so the eventual 1.0 migration guide can be assembled straight from this file.

Entries for `0.8.0` and earlier are short retrospective summaries written when
this file was introduced — they are not exhaustive. Follow the release link in
each one for the full list of merged pull requests.

<!--
Maintaining this file
  - Every user-facing pull request adds its entry under `## [Unreleased]`
    (see CONTRIBUTING.md). Internal-only changes — design docs, CI plumbing,
    dependency bumps of the website — do not need one.
  - Subsections, in this order, keeping only the ones you need:
    `### Breaking Changes` (a deliberate extension of Keep a Changelog, so
    upgraders see it first), `### Added`, `### Changed`, `### Deprecated`,
    `### Removed`, `### Fixed`, `### Security`.
  - Write for someone upgrading the library: what changed, and what they must
    do about it. Link the PR or Issue.
  - English, to match the other community-facing documents. Internal design
    docs under docs/design/ stay Japanese.
  - Releases are automated: .github/workflows/release.yml refuses to release
    while `## [Unreleased]` is empty, then promotes it to
    `## [X.Y.Z] - YYYY-MM-DD` and copies it into the GitHub Release notes
    (scripts/changelog.py). Do not hand-edit released sections.
-->

## [Unreleased]

### Breaking Changes

- Removed seven APIs that had been deprecated long enough to meet the ADR-0005 removal condition — each shipped as deprecated in at least one earlier minor release ([#354](https://github.com/shinyaoguri/metaphor/pull/354)). Migrate as follows:
  - `MetaphorPlugin.onBeforeRender(commandBuffer:time:)` → `pre(commandBuffer:time:)`
  - `MetaphorPlugin.onAfterRender(texture:commandBuffer:)` → `post(texture:commandBuffer:)`
  - `Sketch.draw(_ ctx: SketchContext)` → `draw()`, reaching the context through `self` (for example `self._context`)
  - `Sketch.camera` and `SketchContext.camera` taking nine `Float` arguments → `camera(eye:center:up:)` taking `SIMD3`
  - `Physics2D.addGravity(_:_:)` → `setGravity(_:_:)`
  - `SoundFile.volume` → `gain`
- The two removed `MetaphorPlugin` methods were protocol requirements, so a custom plugin that only implements `onBeforeRender` / `onAfterRender` now compiles but is never called. Rename those methods to `pre` / `post` ([#354](https://github.com/shinyaoguri/metaphor/pull/354)).

### Added

- `CHANGELOG.md` (this file), plus GitHub Release notes generated from it: the release workflow now refuses to publish while `## [Unreleased]` is empty, promotes it to the released version, and puts it above the auto-generated pull request list ([#335](https://github.com/shinyaoguri/metaphor/issues/335))
- `THIRD_PARTY_LICENSES.md`, recording the Simplified BSD license of the [Syphon Framework](https://github.com/Syphon/Syphon-Framework) redistributed as `Syphon.xcframework` ([#340](https://github.com/shinyaoguri/metaphor/pull/340))
- `SECURITY.md` with a private path for reporting vulnerabilities ([#340](https://github.com/shinyaoguri/metaphor/pull/340))
- `CONTRIBUTING.md` and GitHub Issue / pull request templates, including routing between this repository and [`metaphor-cli`](https://github.com/shinyaoguri/metaphor-cli) ([#341](https://github.com/shinyaoguri/metaphor/pull/341))
- Both READMEs now link to the published DocC API reference ([#342](https://github.com/shinyaoguri/metaphor/pull/342))
- `docs/permissions.md` explaining microphone/camera TCC permissions for `swift run` binaries, an English `docs/README.en.md`, expanded README Troubleshooting (Intel Mac, SwiftPM dependency-resolution failures), and `Examples/LEARNING_PATH.md`, a curated "learn in order" route through the example catalog ([#337](https://github.com/shinyaoguri/metaphor/issues/337))

### Changed

- `loadPixels()` on the main canvas now reads back **the canvas as of the call**, matching Processing. Previously it could only return the content committed up to the end of the previous frame, so shapes drawn earlier in the same `draw()` were missing. Calling it mid-`draw()` closes the current render pass, commits it, waits for the GPU, and resumes drawing in a `loadAction = .load` continuation pass — the rendered frame is unchanged, and sketches that never call `loadPixels()` pay nothing. Two consequences to know about: the pass split clears depth, so 3D drawn before and after a `loadPixels()` call is no longer depth-tested against each other; and with shadows enabled the same-frame readback is unavailable (`draw()` runs as a record pass first), in which case the last committed frame is read and a warning is logged once ([#326](https://github.com/shinyaoguri/metaphor/issues/326))

- Published tags and Release assets are now treated as immutable and are enforced as such: `refs/tags/v*` cannot be deleted or moved, every tag's `binaryTarget` URL is health-checked weekly, and a release verifies its own uploaded `Syphon.xcframework.zip` against the checksum in `Package.swift` before telling `metaphor-cli` to pin it. SwiftPM re-fetches that asset on every dependency resolution, so a deleted asset would permanently break the tag for existing users ([#352](https://github.com/shinyaoguri/metaphor/pull/352))

## [0.8.0] - 2026-08-01

Processing parity bundle: data IO (`loadJSON` / `saveJSON` / `loadTable` / `saveTable` / `loadStrings` / `saveStrings`), canvas operations (`applyMatrix` / `resetMatrix` / `shearX` / `shearY` / `screenX` / `screenY` / `screenZ` / `keyTyped` / `copy` / `mask` / `resize`), `selectInput` / `selectOutput` / `fileDropped`, PVector-style mutating methods on `Vec2` / `Vec3`, MSAA sample count in `SketchConfig`, OSC sending (`OSCSender`), path-keyed asset caching for `loadImage` / `loadModel`, SVG export (`beginSVG` / `endSVG`), and `README.en.md`. Fixes a first-frame `copy()` reading uninitialized VRAM. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.8.0)

## [0.7.0] - 2026-07-19

Probe `frame.json` gains a `performance` section (measured frame rate, memory, CPU, thermal state) for AI agents observing a running sketch. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.7.0)

## [0.6.0] - 2026-07-19

App Nap is suppressed by default while a sketch runs, so a backgrounded window keeps its frame rate. Fixes an `IOSurface` leak caused by a `CVMetalTexture` retain cycle and a timer/activity leak on teardown; speeds up large `Canvas3D` shapes and in-place Core Image / MPS filters. CI gains a Swift 5.10 (Xcode 15.4) build check. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.6.0)

## [0.5.3] - 2026-07-11

Multi-camera support: device enumeration and selection, closest-match `activeFormat` for a requested resolution, disconnect detection and permission checks, plus an example. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.5.3)

## [0.5.2] - 2026-07-03

Fixes: 2D physics broadphase missed collisions caused by large constraint moves, a race between Probe sequence directory cleanup and asynchronous writes, `ImageFilterGPU` cache growth on the `encode()` path, and `VideoExporter` state bleeding between consecutive recordings. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.5.2)

## [0.5.1] - 2026-07-02

`arc()` without an explicit mode now matches Processing (pie fill, arc-only stroke), and circle/arc segment counts adapt to size instead of being fixed at 32. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.5.1)

### Breaking Changes

- `arc()` called without a mode draws differently than before (Processing-compatible); pass an explicit mode to keep the old shape.

## [0.5.0] - 2026-07-02

A repository-wide correctness and robustness sweep touching every module (drawing, text, particles, post effects, physics, audio, MIDI/OSC, video, ML, RenderGraph, SceneGraph, export), the ADR-0005 API consistency work, camera/light snapshots in the command-recording path, main-canvas `loadPixels()` readback, and a rebuilt project website. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.5.0)

### Breaking Changes

- The deprecated `make*` bridge factories were removed — use the `create*` equivalents (`createAudioInput()`, `createOSCReceiver()`, `createPhysics2D()`, …), which now validate their arguments and no longer return spurious optionals (ADR-0005 phase 3).

## [0.4.0] - 2026-07-01

The AI-collaboration runtime: Probe image statistics and typed `probe()` values, `capture_sequence` for multi-frame observation, and a `sourceStamp` provenance block (`frame.json` schema v3 → v4). Drawing moves to a unified command stream, so 2D and 3D calls composite in call order. Cross-repository contract guardrails move to a wire-schema source of truth. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.4.0)

### Breaking Changes

- Syphon output moved out of `MetaphorCore` into its own `MetaphorSyphon` module. Users of the `import metaphor` umbrella are unaffected (the output registers itself on load); code importing `MetaphorCore` directly must also import `MetaphorSyphon`.

## [0.3.0] - 2026-06-21

Adds the `MetaphorProbe` plugin (snapshots and state for AI agents), headless rendering and stdin input injection for the live viewer, batched drawing for large circle counts, and a broad fix sweep across MIDI, OSC, audio, GIF export and both canvases. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.3.0)

## [0.2.4] - 2026-05-08

Release-workflow rework: GitHub Flow, a `GITHUB_TOKEN`-only release path, and pre-release tags. No library changes. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.2.4)

## [0.2.3] - 2026-05-04

Adds the `MetaphorVideo` module for video playback, moves `camera()` to SIMD3 signatures, fixes blend-mode alpha attenuation, and triple-buffers the staging texture used by video export. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.2.3)

## [0.2.2] - 2026-04-18

Memory-leak and robustness fixes (secondary windows, `CIFilterWrapper` storage, mesh and particle buffer allocation failures, `NoiseTexture` with no color stops) plus API-consistency renames with deprecated aliases: `Physics2D.addGravity()` → `setGravity()`, `SoundFile.volume` → `gain`, argument labels on the MIDI callbacks, and a public `OSCMessage`. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.2.2)

> **Note** — this release's GitHub Release page carries no assets; its `Package.swift` points at the `v0.2.1` asset instead. Deleting the `v0.2.1` asset would break both tags. See [docs/releasing.md](docs/releasing.md).

## [0.2.1] - 2026-03-08

Release plumbing only. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.2.1)

## [0.2.0] - 2026-03-08

Adds `PixelBuffer`, multi-window improvements, Core ML examples (face detection, image classification, person segmentation, style transfer) and the project website. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.2.0)

### Breaking Changes

- iOS support was removed; `metaphor` is macOS-only from this release on.

## [0.1.0] - 2026-01-12

First public release. [Release notes](https://github.com/shinyaoguri/metaphor/releases/tag/v0.1.0)

[Unreleased]: https://github.com/shinyaoguri/metaphor/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/shinyaoguri/metaphor/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/shinyaoguri/metaphor/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/shinyaoguri/metaphor/compare/v0.5.3...v0.6.0
[0.5.3]: https://github.com/shinyaoguri/metaphor/compare/v0.5.2...v0.5.3
[0.5.2]: https://github.com/shinyaoguri/metaphor/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/shinyaoguri/metaphor/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/shinyaoguri/metaphor/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/shinyaoguri/metaphor/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/shinyaoguri/metaphor/compare/v0.2.4...v0.3.0
[0.2.4]: https://github.com/shinyaoguri/metaphor/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/shinyaoguri/metaphor/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/shinyaoguri/metaphor/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/shinyaoguri/metaphor/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/shinyaoguri/metaphor/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/shinyaoguri/metaphor/releases/tag/v0.1.0
