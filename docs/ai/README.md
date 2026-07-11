# AI Development Guide

**Pick your entry point first** — this file is for implementers only:

| You want to… | Read |
|---|---|
| Write or fix a sketch (most users and AI agents) | `llms-sketch.txt`, then [for-sketch-authors.md](for-sketch-authors.md) |
| Look up public API signatures | `llms.txt` (generated, complete) |
| Find a working example to adapt | [examples-index.md](examples-index.md) — machine-readable queries via `examples-index.json` |
| Prompt templates for common tasks | [prompts/](prompts/) |
| Debug or extend the metaphor implementation itself | **this file** (everything below) |
| See which AI files are available per install method | [install-scenarios.md](install-scenarios.md) |

Everything below this line is for **implementers** — people (or agents)
changing metaphor's own source. It complements `llms.txt`: signatures live
there; implementation structure, debugging recipes, and extension notes live
here.

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
- Zero-copy shared-storage paths (`Compute/GPUBuffer`, `Drawing/PixelBuffer`,
  the glyph atlas `replace()` in `TextRenderer`) trade safety for latency by
  design: an immediate CPU write can race an in-flight GPU read of a previous
  frame. The contract is **write before the frame's draw calls that read the
  resource** (setup or the top of `draw()`), not mid-frame after submitting
  work that samples it. Do not "fix" these paths by adding blocking waits;
  if a use case genuinely needs mid-frame mutation, triple-buffer that
  resource instead (see #164).
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
