# AI Development Guide

This guide complements `llms.txt`. Use `llms.txt` for public API signatures; use
this file when debugging or extending the implementation.

For content creators using metaphor with an AI assistant, start with
`llms-sketch.txt` and `docs/ai/for-sketch-authors.md`.
Use `docs/ai/examples-index.md` to find nearby working examples before asking
the assistant to invent a sketch from scratch.
Prompt templates live in `docs/ai/prompts/`.
See `docs/ai/install-scenarios.md` for how this works across direct SwiftPM
dependencies, local library checkouts, Homebrew CLI installs, release
installers, and source checkouts.

## Orientation

- Public sketch code usually enters through `Sketch` extensions in
  `Sources/MetaphorCore/Sketch/` or bridge extensions in `Sources/metaphor/`.
- `SketchContext` is the routing layer. It owns user-visible state and delegates
  rendering calls to `Canvas2D`, `Canvas3D`, exporters, compute helpers, and
  optional subsystem bridges.
- `Canvas2D` / `Canvas3D` are the Metal backends. They should keep public API
  behavior Processing-like while preserving GPU batching and resource reuse.
- `MetaphorRenderer` owns the frame lifecycle: compute, render, shadow,
  RenderGraph, post-process, then plugin `post()` (output phase), then blit.
- Frame output (Syphon etc.) is a plugin via `MetaphorOutputPlugin.post()`, not
  hardcoded in the renderer. `MetaphorCore` does NOT depend on Syphon; the
  `MetaphorSyphon` target owns the `Syphon` binaryTarget and registers its output
  factory into `MetaphorOutputRegistry` at load (C constructor). `SketchRunner`
  auto-wires output transparently via the registry. See ADR 0001.
- Tier 1 modules (`MetaphorAudio`, `MetaphorNetwork`, `MetaphorPhysics`,
  `MetaphorML`, `MetaphorVideo`) must not depend on `MetaphorCore`.
- Tier 2 modules (`MetaphorNoise`, `MetaphorMPS`, `MetaphorCoreImage`,
  `MetaphorRenderGraph`, `MetaphorSceneGraph`, `MetaphorSyphon`) may depend on
  `MetaphorCore` and are surfaced through the umbrella under `Sources/metaphor/`.

## Debugging Map

- Build/setup failures: `Package.swift`, `Makefile`, `scripts/preflight-check.sh`,
  `scripts/build-syphon.sh`.
- Missing public API in AI docs: `Makefile` `symbol-graphs`, then
  `scripts/generate-llms-txt.py`, then regenerate `llms.txt`.
- Sketch lifecycle or input bugs: `SketchRunner.swift`, `SketchContext.swift`,
  `InputManager.swift`, `MetaphorRenderer.swift`.
- 2D drawing bugs: start at the relevant `Sketch+*.swift` wrapper, then
  `SketchContext+*.swift`, then `Canvas2D*.swift`.
- 3D drawing bugs: `Sketch+3D.swift`, `SketchContext+3D.swift`, `Canvas3D.swift`,
  `Mesh.swift`, `PipelineFactory.swift`, shader files.
- Shader failures: keep `Shaders/Metal/*.metal`, `Shaders/ShaderSources/*.txt`,
  and shader function constants in sync.
- Export/readback bugs: `FrameExporter.swift`, `VideoExporter.swift`,
  `GIFExporter.swift`, `RenderTestHelper.swift`.
- Observability (Probe / input injection) runtime cost: `MetaphorProbePlugin.swift`,
  `InputInjectionPlugin.swift`, plugin dispatch in `MetaphorRenderer.swift`,
  `MetaphorRenderer.probePlugin` cache used by `Sketch+Probe.swift`.

## Invariants

- Public API changes under `Sources/**/*.swift` require `make llms-txt` and a
  committed `llms.txt` update.
- Every library product in `Package.swift` should be included in `Makefile`'s
  `symbol-graphs` target unless it intentionally has no public symbols.
- `import metaphor` should continue to re-export every public module and expose
  bridge conveniences for optional subsystems.
- Triple-buffered resources use a 3-buffer rotation. Keep CPU writes and GPU
  reads separated by `frameBufferIndex` / `bufferIndex` conventions.
- Compute work that feeds rendering must preserve the renderer's explicit
  compute-to-render synchronization.
- Runtime drawing failures generally warn and skip work; initialization and
  resource creation failures should throw typed errors where possible.
- Observability must not tax the render loop (Issue #118). When Probe / input
  injection are OFF (no plugin registered — the normal `swift run` and the
  human live viewer), the frame loop's plugin dispatch is zero-cost and
  `Sketch.probe(_:_:)` is a complete no-op. When ON (MCP / headless), `pre()`
  stays light (state reset + one `stat()`), `post()` returns immediately unless
  a request is pending, and heavy readback/PNG/JSON work runs on demand and off
  the render thread via `deferReadback`. `Sketch.probe` resolves the plugin
  through the cached `MetaphorRenderer.probePlugin` (no per-call scan). Regression
  guards live in `Tests/metaphorTests/ObservabilityOverheadTests.swift`; keep
  them green when touching plugin dispatch, `probe(...)`, or the probe hot path.

## Verification

- Run `make ai-docs-check` after changing AI-facing docs, module lists, or
  version snippets.
- Run `make llms-txt` after public API edits.
- Run focused Swift tests with `swift test --filter <SuiteOrTestName>` while
  iterating, then `make test` before handing off broader changes.
- For rendering behavior, prefer pixel/readback tests via `MetaphorTestSupport`
  over visual-only examples.
