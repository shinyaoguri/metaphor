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
  - Do NOT add entries here by hand. A user-facing pull request adds one file
    per change to changelog.d/ (`<slug>.<category>.md` — see
    changelog.d/README.md and CONTRIBUTING.md); the release workflow folds them
    into `## [Unreleased]` and promotes that to the released version. One file
    per change means concurrent pull requests never conflict over these lines,
    which is what the old "append to Unreleased" rule caused. Internal-only
    changes — design docs, CI plumbing, dependency bumps of the website — do
    not need an entry at all.
  - Writing directly under `## [Unreleased]` still works and is still
    collected; it is the escape hatch for a hotfix on a branch where
    changelog.d/ has already been drained, not the everyday path.
  - Subsections, in this order, keeping only the ones you need:
    `### Breaking Changes` (a deliberate extension of Keep a Changelog, so
    upgraders see it first), `### Added`, `### Changed`, `### Deprecated`,
    `### Removed`, `### Fixed`, `### Security`.
  - Write for someone upgrading the library: what changed, and what they must
    do about it. Link the PR or Issue.
  - English, to match the other community-facing documents. Internal design
    docs under docs/design/ stay Japanese.
  - Releases are automated: .github/workflows/release.yml refuses to release
    while changelog.d/ and `## [Unreleased]` are both empty, then collects,
    promotes to `## [X.Y.Z] - YYYY-MM-DD` and copies it into the GitHub Release
    notes (scripts/changelog.py). Do not hand-edit released sections.
-->

## [Unreleased]

## [0.8.1] - 2026-08-10

### Breaking Changes

- **`mouseButton` is now a `MouseButton?` instead of an `Int`.** The new enum has `left`, `right` and `middle` cases ([#382](https://github.com/shinyaoguri/metaphor/issues/382)). The old `Int` made the Processing idiom `if mouseButton == LEFT` **compile and always evaluate to `false`**: metaphor's `LEFT` is the left-arrow virtual key code (`UInt16` 123), and Swift permits heterogeneous integer comparison, so nothing diagnosed it. That comparison is now a compile error. Migrate `mouseButton == 0` / `1` / `2` to `mouseButton == .left` / `.right` / `.middle`; no `Int`-typed alias is provided, deliberately, because it would re-open the exact `== LEFT` hole this change closes.
  - The property is **optional**: it is `nil` until the first press, which the old `Int` could not express (`0` meant both "left" and "never pressed"). After a press it keeps the last pressed button even once released — as in Processing — so `mouseReleased()` can still tell which button was let go. Ask `isMousePressed` whether a button is down right now.
  - `MetaphorPlugin.mouseEvent(x:y:button:type:)` takes `button: MouseButton?`, `nil` for the buttonless `.moved` / `.dragged` / `.scrolled` events (it used to receive a meaningless `0`). **This is a protocol requirement**, so a plugin still declaring `button: Int` compiles but silently stops being called, exactly like the `pre` / `post` rename above — update the signature. `InputManager.onMousePressed` / `onMouseReleased` / `onMouseClicked` now hand a `MouseButton` to their closures.
  - The stdin JSON Lines input protocol is **unchanged**: its `button` field stays an integer (`0` / `1` / `2`), per CONTRACT.md contract point 3. The conversion happens inside metaphor, so `metaphor-cli` needs no update.
- **`cylinder`, `cone` and `torus` no longer default their size arguments.** `cylinder(radius:height:detail:)`, `cone(radius:height:detail:)` and `torus(ringRadius:tubeRadius:detail:)` used to default to `radius: 0.5` / `height: 1` / `tubeRadius: 0.2` — world units left over from an earlier design. The default camera is pixel space (one world unit is one pixel), so those defaults drew a one-pixel object that is invisible in practice, and `box` / `sphere` / `plane` already required their sizes. The size arguments are now required at every layer (`Sketch`, `SketchContext`, `Canvas3D`, `Graphics3D`); the quality argument `detail: Int = 24` keeps its default, matching `sphere(_:detail:)` ([#380](https://github.com/shinyaoguri/metaphor/issues/380)). A call that omitted a size no longer compiles — pass pixel sizes, e.g. `cylinder(radius: 50, height: 100)`, `torus(ringRadius: 120, tubeRadius: 40)`. To keep the old geometry exactly, pass the former defaults explicitly (`cylinder(radius: 0.5, height: 1)`). The low-level `Mesh.cylinder` / `Mesh.cone` / `Mesh.torus` builders are unchanged and still default to a unit-sized mesh.
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
- `docs/api-stability-policy.md`, the API stability policy: what counts as public API across the four layers (and what does not), source compatibility with no ABI guarantee, the deprecation window, where rendering output / the Probe wire schema / stdin / environment variables sit under SemVer, the frozen `@_exported import Metal / MetalKit / simd`, supported platforms, and the `0.9.x` freeze discipline. Both READMEs also now state that the project is maintained by one person on a best-effort basis ([#338](https://github.com/shinyaoguri/metaphor/issues/338))
- `docs/processing-migration-guide.md`, a "the Processing X is metaphor's Y" mapping table plus a pitfalls collection (value vs reference types, `@MainActor`, the two color ranges, the 2D/3D transform split, `loadPixels()` pass splitting, `LEFT` being a key code rather than an alignment constant) and an explicit list of Processing APIs that are not implemented yet. Linked from both READMEs ([#336](https://github.com/shinyaoguri/metaphor/issues/336))
- `@Param` declares a tunable sketch property that **persists across restarts** and can be
  changed **without rebuilding**. Values live in a `ParameterStore` (`SketchContext.params`),
  are written atomically to `.metaphor/params/params.json`, and are restored on the next
  launch before `setup()` runs. External tools and AI agents change them by writing
  `.metaphor/params/set-request.json` (`{"id": "<unique>", "values": {…}}`); the next frame
  applies it and echoes `appliedRequestId` / `revision`, with rejected values explained in
  `warnings`. Supported types: `Float` / `Double` / `Int` / `Bool` / `String` (optional
  `choices`) / `Color` / `Vec2` / `Vec3`; `min` / `max` clamp external writes.

  ```swift
  @main final class MySketch: Sketch {
      @Param(min: 10, max: 200) var radius: Float = 50
      @Param(choices: ["add", "multiply"]) var mode: String = "add"

      func draw() { circle(width / 2, height / 2, radius) }
  }
  ```

  Enabled automatically when a sketch declares at least one `@Param` (no CLI needed);
  opt out with `METAPHOR_PARAMS=0`. The file formats are cross-repo contract point 7
  ([CONTRACT.md](https://github.com/shinyaoguri/metaphor/blob/main/CONTRACT.md),
  [#419](https://github.com/shinyaoguri/metaphor/issues/419))
- `gui.params()` draws a live control panel for every `@Param` a sketch declares — one line,
  no wiring. The panel and an AI agent writing `.metaphor/params/set-request.json` are
  symmetric clients of the same `ParameterStore`, so a value dragged on a slider is
  persisted to `.metaphor/params/params.json` and restored on the next launch.

  ```swift
  @main final class MySketch: Sketch {
      @Param(min: 10, max: 200) var radius: Float = 50
      @Param var showGrid: Bool = true
      @Param(choices: ["cool", "warm"]) var palette: String = "cool"

      func draw() {
          gui.params()                              // sliders / toggles / pickers
          circle(width / 2, height / 2, radius)
      }
  }
  ```

  Widgets follow the declared type: `Float` / `Int` become sliders, `Bool` a toggle,
  `Color` an RGB picker, `Vec2` / `Vec3` component sliders, and a `String` with `choices`
  a button that cycles through them. Numbers declared without `min` / `max` get a stable
  auto range derived from their first displayed value. `gui.param("radius")` places a
  single parameter when you want to lay the panel out yourself, and the existing immediate
  mode (`gui.slider("x", &x, …)`) is unchanged. New example:
  `Examples/Samples/ParameterPanel`
  ([#422](https://github.com/shinyaoguri/metaphor/issues/422))
- A Probe snapshot now carries the parameters that produced it. `frame.json` gains an
  additive `params` section — `{"revision": 7, "values": {"radius": 120.0, …}}` — so an AI
  agent reading a frame knows exactly which `@Param` values were in effect, instead of
  reading `.metaphor/params/params.json` separately and hoping nothing changed in between.
  `revision` matches the store's counter, which makes "is this the frame after my
  `set_param`?" a comparison rather than a guess.

  The section is omitted for sketches that declare no `@Param`, and for failure responses.
  Unlike `performance`, it is also written for every frame of a `capture_sequence` run
  (reading the store costs no syscall), so sweeping a parameter during a capture stays
  legible frame by frame. Type, range and `choices` remain canon in `params.json`;
  `frame.json` carries values only. Wire format: `schemaVersion` stays 4 (additive),
  contract point 4 in [CONTRACT.md](https://github.com/shinyaoguri/metaphor/blob/main/CONTRACT.md)
  ([#424](https://github.com/shinyaoguri/metaphor/issues/424))
- `vertex(x, y, z, u, v)` gives a `beginShape3D()` vertex its texture
  coordinates, so `texture(img)` now applies to custom 3D shapes. Until now the
  3D vertex format had no UV channel and a textured `beginShape3D()` silently
  rendered with the current fill; the five shipped `Topics/Textures` examples
  (`TextureQuad` / `TextureCube` / `TextureSphere` / `TextureTriangle` /
  `TextureCylinder`) now show their textures. `u` / `v` are normalized (0…1),
  the UV travels with its vertex through every tessellation mode, and a shape
  whose vertices carry no UV keeps rendering with the fill exactly as before
  ([#433](https://github.com/shinyaoguri/metaphor/issues/433))
- `DynamicMesh.addTexCoord(u, v)` (and `setTexCoord(index:_:)`) gives a dynamic
  mesh its texture coordinates, so `texture(img)` now applies to
  `dynamicMesh(mesh)` as well. Until now `DynamicMesh` carried only
  position / normal / color, and a textured dynamic mesh silently rendered with
  the current fill. `u` / `v` are normalized (0…1), UV stays aligned with its
  vertex through `setVertex` / indexed drawing, and a mesh that never declares a
  texture coordinate keeps rendering with the fill exactly as before. Textures
  also survive the recorded path (shadows / `METAPHOR_COMMAND_RECORD`). New
  sample: `Examples/Samples/DynamicMeshTexture`
  ([#435](https://github.com/shinyaoguri/metaphor/issues/435))
- `drawInstanced(mesh, transforms:)` (and the `colors:` overload) draws one mesh
  at many transforms in a single call. Each instance is placed at
  `currentTransform * transforms[i]`, so it is equivalent to a
  `pushMatrix()` / `applyMatrix(t)` / `mesh(m)` / `popMatrix()` loop — but the
  per-instance state evaluation (batch key, matrix composition, normal matrix)
  happens once instead of N times (20k cubes: ~15ms → ~11ms of CPU encoding in a
  debug build). `colors` sets the fill color per instance; entries beyond
  `transforms` are ignored and missing ones fall back to the current fill.
  Stroke color, material and texture stay shared across instances. Works on the
  recorded path (shadows / `METAPHOR_COMMAND_RECORD`) too, where all instances
  share one draw sequence number. New sample: `Examples/Samples/InstancedCubes`
  ([#442](https://github.com/shinyaoguri/metaphor/issues/442))
- Primitive meshes can now be created from the sketch layer, without reaching for
  `MTLDevice`: `createBoxMesh(_:_:_:)` / `createBoxMesh(_:)` / `createSphereMesh(_:detail:)` /
  `createPlaneMesh(_:_:)` / `createCylinderMesh(radius:height:detail:)` /
  `createConeMesh(radius:height:detail:)` / `createTorusMesh(ringRadius:tubeRadius:detail:)`.
  Each takes the same arguments as the matching drawing primitive (`box`, `sphere`, …) and
  returns the same geometry as a `Mesh` value, ready for `mesh(_:)` and
  `drawInstanced(_:transforms:)`. Repeated calls with the same arguments return the same
  instance, so create meshes in `setup()` rather than per frame
  ([#443](https://github.com/shinyaoguri/metaphor/issues/443))

  ```swift
  // before
  let cube = try? Mesh.box(device: context.renderer.device, width: 12, height: 12, depth: 12)
  // after
  let cube = createBoxMesh(12)
  ```
- `saveState()` / `restoreState(_:)` carry a sketch's own state across a live
  reload, and `SketchConfig(preserveClock: true)` carries `frameCount` and `time`
  with no sketch code at all. Both are optional: the default implementations are
  `nil` / no-op, and a failed decode silently keeps the initial state instead of
  breaking the reload. `encodeState` / `decodeState` wrap `Codable` payloads.
  The state travels through a new file contract (`.metaphor/state/state.json` +
  `save-request.json`, CONTRACT.md point 8) in the same style as Probe and the
  Parameter Store — atomic writes, mtime polling, `id` echo — so it works with
  `metaphor watch` and by hand alike. Enabled automatically in headless
  (`metaphor watch`) runs; `METAPHOR_STATE=1` turns it on for a plain
  `swift run`, `METAPHOR_STATE=0` off. New sample:
  `Examples/Samples/StatePreservation`
  ([#451](https://github.com/shinyaoguri/metaphor/issues/451))

### Changed

- `loadPixels()` on the main canvas now reads back **the canvas as of the call**, matching Processing. Previously it could only return the content committed up to the end of the previous frame, so shapes drawn earlier in the same `draw()` were missing. Calling it mid-`draw()` closes the current render pass, commits it, waits for the GPU, and resumes drawing in a `loadAction = .load` continuation pass — the rendered frame is unchanged, and sketches that never call `loadPixels()` pay nothing. Two consequences to know about: the pass split clears depth, so 3D drawn before and after a `loadPixels()` call is no longer depth-tested against each other; and with shadows enabled the same-frame readback is unavailable (`draw()` runs as a record pass first), in which case the last committed frame is read and a warning is logged once ([#326](https://github.com/shinyaoguri/metaphor/issues/326))

- Published tags and Release assets are now treated as immutable and are enforced as such: `refs/tags/v*` cannot be deleted or moved, every tag's `binaryTarget` URL is health-checked weekly, and a release verifies its own uploaded `Syphon.xcframework.zip` against the checksum in `Package.swift` before telling `metaphor-cli` to pin it. SwiftPM re-fetches that asset on every dependency resolution, so a deleted asset would permanently break the tag for existing users ([#352](https://github.com/shinyaoguri/metaphor/pull/352))
- Every public throwing API now documents the concrete error cases it throws in its `- Throws:` line, and `MetaphorError` documents the contract itself. ADR-0005's "resource creation uses typed throws" is now realised as a documented single-error-type contract rather than the `throws(E)` syntax: typed throws (SE-0413) is a Swift 6.0 feature and the library still supports Swift 5.10, so applying the syntax is deferred until that minimum is raised — at which point it becomes a mechanical change with no behavioural difference ([#323](https://github.com/shinyaoguri/metaphor/issues/323))
- `setRenderGraph(_:)` and `setClearColor(_:_:_:_:)` document their naming explicitly: passing `nil` to the former is how you clear the active render graph (there is no separate `clearRenderGraph()`), and the `clear` in the latter is the Metal noun "clear color", not the deleting `clear*` verb used by `clearPostEffects()` ([#322](https://github.com/shinyaoguri/metaphor/issues/322))
- `ambientLight()` and `lights()` now document the default ambient level on every layer (`Sketch`, `SketchContext`, `Graphics3D`, `Canvas3D`): the ambient that `lights()` — or the first light you add — installs for you is **30% of the current `colorMode` range**, i.e. `ambientLight(76.5)` in the default 0–255 range. It was previously written as a raw `0.3` in the source, which read as if `ambientLight(0.3)` would reproduce it when in fact that value is 1/255 of it. Rendering is unchanged, bit for bit ([#392](https://github.com/shinyaoguri/metaphor/issues/392))
- **Every module now builds warning-free under Swift 6 strict concurrency**, on both the newest toolchain and the oldest supported one (Swift 5.10 / Xcode 15.4), and CI keeps it that way — `build-and-test` already compiled with `-warnings-as-errors`, `build-swift-5-10` now does too, and a manifest check refuses a new target that forgets the setting. Public signatures are unchanged; the only observable difference is that `MetaphorRenderer`'s two `MTKViewDelegate` methods (`draw(in:)`, `mtkView(_:drawableSizeWillChange:)`) are now `nonisolated` and assert main-actor isolation internally, because the requirement is not main-actor-isolated in the 5.10 SDK. Along the way `@preconcurrency import` went from 29 occurrences to 13 — every one was removed and only those the compiler still demands were put back, each with a comment saying why. This is the groundwork for adopting the Swift 6 language mode once the minimum toolchain is raised ([#328](https://github.com/shinyaoguri/metaphor/issues/328))
- Failure modes are now documented explicitly in three places, with no behavior change: the `SoundFile` usage example shows `do`/`catch` instead of `try!`, which would crash the sketch on a missing or undecodable file; `GPUBuffer`'s subscript states that out-of-range access traps, matching `Swift.Array`; and the gradient-stop noise texture APIs state that fewer than 2 color stops return nil, now locked by tests ([#374](https://github.com/shinyaoguri/metaphor/pull/374))
- Changelog entries now live one-per-file in [`changelog.d/`](https://github.com/shinyaoguri/metaphor/tree/main/changelog.d) instead of being appended to `## [Unreleased]` by every pull request, which made concurrent pull requests conflict on the same lines almost every time. `scripts/changelog.py collect` folds them into `## [Unreleased]` at release time (and `changelog.py release` runs it first), so the published changelog is unchanged — only the way contributors write into it is. Writing under `## [Unreleased]` directly still works

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

### Fixed

- `screenY(x, y, z)` (3D) returned a y coordinate mirrored relative to the 2D `screenY(x, y)`, because `Canvas3D.screenPosition(_:_:_:)` mapped NDC y to pixel space with the same `(ndc + 1) / 2` formula used for x, without accounting for the Y-flip already baked into the view-projection matrix ([#378](https://github.com/shinyaoguri/metaphor/issues/378)). A point above the canvas center now correctly reports a smaller `screenY`, matching the 2D API's left-top-origin, Y-down convention. `screenX(x, y, z)` and `screenZ(x, y, z)` were unaffected.
- With `enableShadows()`, the shadow factor is now applied to **direct light only** (diffuse + specular). Ambient light, emissive colour and the PBR ambient-occlusion factor are no longer folded into the shadow attenuation, in both the Blinn-Phong and PBR paths ([#364](https://github.com/shinyaoguri/metaphor/issues/364)). Previously an emissive material went completely dark inside a shadow, and `ambientOcclusion()` was cancelled there, making shadowed surfaces *brighter* than the lit ones next to them. **Shaded output can change for sketches that call `emissive()` or `ambientOcclusion()` together with `enableShadows()`** — shadowed areas of those materials now keep their emissive glow and their occlusion. Materials that use neither (the default) render exactly as before, bit for bit. `ambientLight()` and `directionalLight()` also document two conventions that are easy to get wrong: ambient takes a value in the current `colorMode` range (0–255 by default, so `ambientLight(0.35)` is essentially black), and a light direction is the direction the light *travels* in a y-down world, so `directionalLight(0, 1, 0)` is the one that shines from above.
- `frameRate(0)` and negative values are now clamped to `1` before reaching `renderer.targetFPS` (which Probe's `frame.json` reports verbatim) and `MTKView.preferredFramesPerSecond`, with a `metaphorWarning` when clamping happens ([#358](https://github.com/shinyaoguri/metaphor/issues/358)). Previously the `max(fps, 1)` clamp was only applied to the timer-loop interval calculation, so the displayLink path (`MTKView.preferredFramesPerSecond`) and the reported `targetFPS` silently received `0` or negative values — `0` means "as fast as possible" for `MTKView`, and Probe consumers (AI agents) would read an invalid frame rate. `frameRate(_:)` still forwards its argument verbatim from `Sketch` through `SketchContext`; the clamp is applied once, at the entry of `SketchRunner`'s internal frame-rate handler, so it covers `targetFPS`, the timer interval, and `MTKView` uniformly.
- `llms.txt` now lists the API you write at a **declaration site** rather than only the API
  that appears in a `Sketch` signature. Two whole families of public symbols were invisible
  to AI agents reading it:

  - **`@Param`** — the property wrapper is spelled at the declaration (`@Param(min: 10,
    max: 200) var radius: Float = 50`) and so appears in no method signature. It is now
    emitted with its `@propertyWrapper` attribute intact
    ([#421](https://github.com/shinyaoguri/metaphor/issues/421))
  - **Extensions on types metaphor does not own** — the PVector-style vector API
    (`normalized()` / `limited(_:)` / `heading()` / `rotated(_:)` / `dist(to:)` /
    `lerp(to:t:)` / `setMag(_:)` and the `mutating` variants on `Vec2` / `Vec3`), the
    `simd_float4x4` helpers, and the `ParamRepresentable` conformances on `Float` / `Int` /
    `Bool` / `String` / `Color`. These exist only because metaphor adds them, so `llms.txt`
    was the one place they could be discovered — and it omitted all of them
    ([#298](https://github.com/shinyaoguri/metaphor/issues/298))

  A symbol documented with a `- Parameters:` block but no abstract also no longer shows the
  first parameter's description as its summary. No API changed — only what the generated
  reference reports about it.
- Ten shipped examples that build 3D geometry with `beginShape()` + `vertex(x, y, z)`
  now use `beginShape3D()` / `endShape3D()`, so they render as solids again instead of
  collapsing into a plane (`Topics/Geometry/{Vertices,ShapeTransform,RGBCube,Toroid}`,
  `Topics/Textures/{TextureQuad,TextureCube,TextureSphere,TextureTriangle,TextureCylinder}`,
  `Demos/Graphics/Patch`). The library behaviour is unchanged — `beginShape()` still
  records into the 2D canvas — but the first `vertex(x, y, z)` inside a 2D `beginShape()`
  now logs a one-shot warning in debug builds pointing at `beginShape3D()`
  ([#387](https://github.com/shinyaoguri/metaphor/issues/387))
- 3D shapes now draw their wireframe in the stroke color instead of blending it
  with the fill color. The stroke pass reused the vertex colors baked in at
  `vertex()` time (the fill color) and multiplied them with the stroke color, so
  a stroke could come out wrong — or vanish entirely when the two colors were
  complementary (a blue fill and a red stroke multiplied to black). Strokes on
  `box()` / `sphere()` and friends were drawn in the fill color for the same
  reason. Wireframes are also depth-biased slightly toward the camera, so the
  lines of a shape that also has a fill are no longer rejected by the depth test
  against their own fill ([#429](https://github.com/shinyaoguri/metaphor/issues/429))
- `dynamicMesh()` now draws its wireframe in the stroke color and depth-biases it
  toward the camera, matching `beginShape3D()` and the mesh primitives. The
  stroke pass was left on the regular pipeline, so it multiplied the per-vertex
  colors set with `addColor()` into the stroke color (a red vertex color and a
  green stroke came out near black), and without the depth bias the lines lost
  the depth test against their own fill and disappeared
  ([#436](https://github.com/shinyaoguri/metaphor/issues/436))
- 3D primitives no longer crash on a non-positive `detail`. `sphere()`,
  `cylinder()`, `cone()`, `torus()` and their `createXxxMesh()` counterparts used
  to hit `Range requires lowerBound <= upperBound` (an untrappable `fatalError`)
  for a negative segment count, and produced degenerate geometry with `inf`/`NaN`
  coordinates for `0`. Segment counts are now clamped at the `Mesh` factories to
  a minimum of 3 (2 for sphere rings), so a `detail` driven from `@Param`, OSC or
  MIDI can pass through zero without killing a live sketch
  ([#445](https://github.com/shinyaoguri/metaphor/issues/445))

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

[Unreleased]: https://github.com/shinyaoguri/metaphor/compare/v0.8.1...HEAD
[0.8.1]: https://github.com/shinyaoguri/metaphor/compare/v0.8.0...v0.8.1
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
