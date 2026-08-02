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

- `translate(x, y)`, `rotate(a)` and `scale(sx, sy)` now apply to the **3D** transform as well as the 2D one, matching Processing's `P3D` semantics ([#325](https://github.com/shinyaoguri/metaphor/issues/325), [#384](https://github.com/shinyaoguri/metaphor/pull/384), ADR-0005 Amendment 2026-08-02). On the 3D matrix they mean a `z = 0` translation, a rotation about z, and a scale that leaves z unchanged. This works because the 3D world is already pixel space — the default camera matches Processing's `P3D` default — so `translate(width/2, height/2)` followed by `box()` now centers the box instead of leaving it at the top-left corner. If a sketch relied on a two-argument transform moving *only* 2D content, wrap that region in `pushMatrix()` / `popMatrix()` (both already save and restore 2D and 3D). Public signatures are unchanged, so this breaks rendering output, not compilation. `shearX`/`shearY` and `applyMatrix(float3x3)` stay 2D-only.
- Removed seven APIs that had been deprecated long enough to meet the ADR-0005 removal condition — each shipped as deprecated in at least one earlier minor release ([#354](https://github.com/shinyaoguri/metaphor/pull/354)). Migrate as follows:
  - `MetaphorPlugin.onBeforeRender(commandBuffer:time:)` → `pre(commandBuffer:time:)`
  - `MetaphorPlugin.onAfterRender(texture:commandBuffer:)` → `post(texture:commandBuffer:)`
  - `Sketch.draw(_ ctx: SketchContext)` → `draw()`, reaching the context through `self` (for example `self._context`)
  - `Sketch.camera` and `SketchContext.camera` taking nine `Float` arguments → `camera(eye:center:up:)` taking `SIMD3`
  - `Physics2D.addGravity(_:_:)` → `setGravity(_:_:)`
  - `SoundFile.volume` → `gain`
- The two removed `MetaphorPlugin` methods were protocol requirements, so a custom plugin that only implements `onBeforeRender` / `onAfterRender` now compiles but is never called. Rename those methods to `pre` / `post` ([#354](https://github.com/shinyaoguri/metaphor/pull/354)).
- **Throwing APIs now throw only their own module's error type.** Previously a number of resource-creation APIs let the underlying framework error escape unchanged — a Metal `NSError` from `makeRenderPipelineState` / `makeLibrary`, a Foundation `NSError` from `String(contentsOfFile:)` / `FileManager`, a MetalKit `NSError` from `MTKTextureLoader`, an AVFoundation `NSError` from `AVAudioFile` / `AVAssetWriter`, or an `NWError` from `NWListener`. Those are now wrapped in `MetaphorError` (or the module's own error type), with the original cause preserved as a string in the case payload. If you were catching a concrete `NSError` / `NWError` from any of the following, catch the metaphor error instead ([#323](https://github.com/shinyaoguri/metaphor/issues/323)):

  | API | Now throws |
  |---|---|
  | `PipelineFactory.build()` / `.buildCompute(device:function:)` | `MetaphorError.pipelineCreationFailed(name:underlying:)` |
  | `ShaderLibrary.register(source:as:)` / `.reload(key:source:)` | `MetaphorError.shaderCompilationFailed(name:underlying:)` |
  | `ShaderLibrary.registerFromFile(path:as:)` / `.reloadFromFile(key:path:)` | `MetaphorError.shaderSourceLoadFailed(path:detail:)`, then the above |
  | `ComputeKernel.init(device:source:functionName:)` / `.init(device:function:)` | `MetaphorError.shaderCompilationFailed` / `.compute(.functionNotFound)` / `.pipelineCreationFailed` |
  | `MImage.init(path:device:)` / `.init(named:device:)` / `.init(nsImage:device:)`, `ResourceLoader.loadImageAsync(...)` | `MetaphorError.image(.loadFailed(source:detail:))` |
  | `Mesh.loadOBJ(device:url:)` | `MetaphorError.mesh(.loadFailed(path:detail:))` |
  | `GIFExporter.endRecord(to:)` / `.endRecordAsync(to:)`, `VideoExporter.beginRecord(...)` | `MetaphorError.export(.fileWriteFailed(path:detail:))` / `.export(.writerFailed(_:))` |
  | `MPSRayTracer.init(device:commandQueue:width:height:)` | `MetaphorError.shaderCompilationFailed` / `.pipelineCreationFailed` |
  | `SoundFile.init(path:)` | `SoundFileError.loadFailed(path:detail:)` |
  | `AudioAnalyzer.start()` | `AudioAnalyzerError.engineStartFailed(detail:)` |
  | `OSCReceiver.start()` | `OSCReceiverError.listenerCreationFailed(port:detail:)` |
  | `GoldenImage.load(pngAt:)` / `.write(pngTo:)` (MetaphorTestSupport) | `GoldenImageError.fileReadFailed(url:detail:)` / `.fileWriteFailed(url:detail:)` |

  Everything reached through those — `loadImage`, `loadSound`, `createComputeKernel`, `createMaterial`, `reloadShader`, `endGIFRecord`, `Canvas2D` / `Canvas3D` / `MetaphorRenderer` initializers, `MergePass.init`, and so on — is covered by the same guarantee. Code that already catches `MetaphorError` (or catches everything) needs no change.

  Carrying those causes required new cases on public error enums (`MetaphorError.shaderSourceLoadFailed`, `MetaphorError.ImageFailure.loadFailed`, `MetaphorError.MeshFailure.loadFailed`, `MetaphorError.ExportFailure.fileWriteFailed`, `SoundFileError.loadFailed`, `AudioAnalyzerError.engineStartFailed`, `OSCReceiverError.listenerCreationFailed`, `GoldenImageError.fileReadFailed` / `.fileWriteFailed`), so an exhaustive `switch` over one of them now needs the extra case or a `default` ([#323](https://github.com/shinyaoguri/metaphor/issues/323)).
- **Five symbols that documented themselves as internal are now `internal`** and no longer appear in the compiled API surface or in `llms.txt` (ADR-0007 Decision 6, [#388](https://github.com/shinyaoguri/metaphor/issues/388)). They were never public API — `docs/api-stability-policy.md` §1 excluded them explicitly — but the access modifier said otherwise, and after the `v0.9.0` freeze removing `public` would require a major release. None of them is referenced by `Examples/`, by [`metaphor-cli`](https://github.com/shinyaoguri/metaphor-cli), or by anything in `CONTRACT.md`:

  | Removed from the public surface | What to use instead |
  |---|---|
  | `MetaphorRenderer.onCaptureOutput` | `MetaphorPlugin.post(texture:commandBuffer:)` — a plugin's output hook, and unlike this single-slot property it composes with other plugins |
  | `MetaphorRenderer.shadowDeferActive` / `.onRecordFrame` / `.onReplayMain` | No replacement. These three wire up the same-frame shadow path (ADR-0003) between `SketchRunner` and the renderer; driving them by hand was never supported |
  | `MetaphorSyphon.SyphonPlugin` | `MetaphorRenderer.startSyphonServer(name:)` / `.stopSyphonServer()` / `.syphonOutput`, or `SketchConfig(syphon:)` — all still public and unchanged |

  `_metaphorSyphonRegister()`, the last underscore-prefixed `public` symbol in the library, is now `internal` as well. It is the `@_cdecl("metaphor_syphon_register")` entry point that a C load-time constructor calls to register the Syphon output factory (ADR-0001); `@_cdecl` emits the C symbol independently of the Swift access level, so automatic Syphon registration is unaffected — re-verified across debug/release × same-package/cross-package.

### Added

- `CHANGELOG.md` (this file), plus GitHub Release notes generated from it: the release workflow now refuses to publish while `## [Unreleased]` is empty, promotes it to the released version, and puts it above the auto-generated pull request list ([#335](https://github.com/shinyaoguri/metaphor/issues/335))
- `THIRD_PARTY_LICENSES.md`, recording the Simplified BSD license of the [Syphon Framework](https://github.com/Syphon/Syphon-Framework) redistributed as `Syphon.xcframework` ([#340](https://github.com/shinyaoguri/metaphor/pull/340))
- `SECURITY.md` with a private path for reporting vulnerabilities ([#340](https://github.com/shinyaoguri/metaphor/pull/340))
- `CONTRIBUTING.md` and GitHub Issue / pull request templates, including routing between this repository and [`metaphor-cli`](https://github.com/shinyaoguri/metaphor-cli) ([#341](https://github.com/shinyaoguri/metaphor/pull/341))
- Both READMEs now link to the published DocC API reference ([#342](https://github.com/shinyaoguri/metaphor/pull/342))
- `docs/permissions.md` explaining microphone/camera TCC permissions for `swift run` binaries, an English `docs/README.en.md`, expanded README Troubleshooting (Intel Mac, SwiftPM dependency-resolution failures), and `Examples/LEARNING_PATH.md`, a curated "learn in order" route through the example catalog ([#337](https://github.com/shinyaoguri/metaphor/issues/337))
- `filter(_ image: MImage, _ type: FilterType)` on the `Sketch` layer. The GPU filter previously existed only on `SketchContext`, so the documented user-facing surface had no entry for it. Use the GPU version while a sketch is running; the CPU version `MImage.filter(_:)` stays available for standalone images that have no renderer ([#322](https://github.com/shinyaoguri/metaphor/issues/322))
- `SoundFile.disableAnalysis()`, the missing counterpart to `enableAnalysis(fftSize:)`. It removes the main-mixer tap and releases the analyzer, after which `spectrum` / `analysisVolume` / `isBeat` / `band(_:)` report their neutral values again ([#322](https://github.com/shinyaoguri/metaphor/issues/322))
- `docs/api-stability-policy.md`, the API stability policy: what counts as public API across the four layers (and what does not, despite being `public`), source compatibility with no ABI guarantee, the deprecation window, where rendering output / the Probe wire schema / stdin / environment variables sit under SemVer, the frozen `@_exported import Metal / MetalKit / simd`, supported platforms, and the `0.9.x` freeze discipline. Both READMEs also now state that the project is maintained by one person on a best-effort basis ([#338](https://github.com/shinyaoguri/metaphor/issues/338))
- `docs/processing-migration-guide.md`, a "the Processing X is metaphor's Y" mapping table plus a pitfalls collection (value vs reference types, `@MainActor`, the two color ranges, the 2D/3D transform split, `loadPixels()` pass splitting, `LEFT` being a key code rather than an alignment constant) and an explicit list of Processing APIs that are not implemented yet. Linked from both READMEs ([#336](https://github.com/shinyaoguri/metaphor/issues/336))

### Changed

- `loadPixels()` on the main canvas now reads back **the canvas as of the call**, matching Processing. Previously it could only return the content committed up to the end of the previous frame, so shapes drawn earlier in the same `draw()` were missing. Calling it mid-`draw()` closes the current render pass, commits it, waits for the GPU, and resumes drawing in a `loadAction = .load` continuation pass — the rendered frame is unchanged, and sketches that never call `loadPixels()` pay nothing. Two consequences to know about: the pass split clears depth, so 3D drawn before and after a `loadPixels()` call is no longer depth-tested against each other; and with shadows enabled the same-frame readback is unavailable (`draw()` runs as a record pass first), in which case the last committed frame is read and a warning is logged once ([#326](https://github.com/shinyaoguri/metaphor/issues/326))

- Published tags and Release assets are now treated as immutable and are enforced as such: `refs/tags/v*` cannot be deleted or moved, every tag's `binaryTarget` URL is health-checked weekly, and a release verifies its own uploaded `Syphon.xcframework.zip` against the checksum in `Package.swift` before telling `metaphor-cli` to pin it. SwiftPM re-fetches that asset on every dependency resolution, so a deleted asset would permanently break the tag for existing users ([#352](https://github.com/shinyaoguri/metaphor/pull/352))
- Every public throwing API now documents the concrete error cases it throws in its `- Throws:` line, and `MetaphorError` documents the contract itself. ADR-0005's "resource creation uses typed throws" is now realised as a documented single-error-type contract rather than the `throws(E)` syntax: typed throws (SE-0413) is a Swift 6.0 feature and the library still supports Swift 5.10, so applying the syntax is deferred until that minimum is raised — at which point it becomes a mechanical change with no behavioural difference ([#323](https://github.com/shinyaoguri/metaphor/issues/323))
- `setRenderGraph(_:)` and `setClearColor(_:_:_:_:)` document their naming explicitly: passing `nil` to the former is how you clear the active render graph (there is no separate `clearRenderGraph()`), and the `clear` in the latter is the Metal noun "clear color", not the deleting `clear*` verb used by `clearPostEffects()` ([#322](https://github.com/shinyaoguri/metaphor/issues/322))
- Failure modes are now documented explicitly in three places, with no behavior change: the `SoundFile` usage example shows `do`/`catch` instead of `try!`, which would crash the sketch on a missing or undecodable file; `GPUBuffer`'s subscript states that out-of-range access traps, matching `Swift.Array`; and the gradient-stop noise texture APIs state that fewer than 2 color stops return nil, now locked by tests ([#374](https://github.com/shinyaoguri/metaphor/pull/374))

### Deprecated

- The recording APIs are renamed so that every family reads `begin<Media>Record` / `end<Media>Record`, and the two `async` overloads that shared a name with their synchronous counterparts gain an `Async` suffix (ADR-0007, [#322](https://github.com/shinyaoguri/metaphor/issues/322)). The old names still work but now warn; they will be **removed in the next minor release**, so migrate now:

  | Deprecated | Use instead |
  |---|---|
  | `beginSVG(_:)` / `endSVG()` | `beginSVGRecord(_:)` / `endSVGRecord()` |
  | `beginRecord(directory:pattern:)` / `endRecord()` | `beginFrameRecord(directory:pattern:)` / `endFrameRecord()` |
  | `endGIFRecord(_:) async throws` | `endGIFRecordAsync(_:)` |
  | `endVideoRecord() async` (and `VideoExporter.endRecord() async`) | `endVideoRecordAsync()` (and `VideoExporter.endRecordAsync()`) |
  | `dispatch(_:threads:_:)` / `dispatch(_:width:height:_:)` | `dispatch(_:threads:configure:)` / `dispatch(_:width:height:configure:)` |

  The old plain `beginRecord()` was the one that clashed with Processing's `beginRecord()` (which starts *vector* recording, not a PNG sequence) — `beginFrameRecord` / `beginSVGRecord` remove that trap. `beginOfflineRender()` / `endOfflineRender()` keep their names: they switch rendering *mode* rather than start a recording.

  The two `dispatch` changes only add a `configure:` label to the trailing closure, so the usual trailing-closure call site (`dispatch(kernel, threads: n) { ... }`) is unchanged and keeps compiling without a warning. Only calls that pass the closure as an explicit final argument need updating.

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
