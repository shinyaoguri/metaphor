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
  `MetaphorSyphon` target owns the `Syphon` binaryTarget and registers a
  `MetaphorOutputProvider` into `MetaphorOutputProviders` at load (C constructor).
  `SketchRunner` / `SketchWindow` scan every registered provider with a
  `MetaphorOutputContext` (config + env + headless) and attach whatever they
  return; providers and `PluginFactory` declare `PluginRequirements`
  (`.externalRenderLoop`) so the render-loop mode is decided before plugins are
  instantiated. `MetaphorOutputRegistry.factory` is a deprecated shim. See ADR 0001
  (runtime split) and ADR 0014 (provider registration / Syphon plugin split).
- Tier 1 modules (`MetaphorAudio`, `MetaphorNetwork`, `MetaphorPhysics`,
  `MetaphorML`, `MetaphorVideo`) must not depend on `MetaphorCore`.
- Tier 2 modules (`MetaphorNoise`, `MetaphorMPS`, `MetaphorCoreImage`,
  `MetaphorRenderGraph`, `MetaphorSceneGraph`, `MetaphorSyphon`) may depend on
  `MetaphorCore` and are surfaced through the umbrella under `Sources/metaphor/`.
- `MetaphorLog` sits below Core (Tier 0, zero dependencies) so every tier can use
  the same diagnostics. Never write `print("[metaphor] …")` outside `MetaphorCore`:
  pick `metaphorWarning` (stdout, DEBUG only — the caller passed a bad value),
  `metaphorAlert` (stderr, always — the caller is right but the environment is
  silently broken), or `metaphorDiagnostic` (stderr, `METAPHOR_DEBUG=1` only —
  ignorable internal events worth isolating). The table in
  `Sources/MetaphorLog/Log.swift` is the source of truth, and
  `Tests/metaphorTests/LogConventionTests.swift` enforces it. `MetaphorCore` still
  holds a few raw `print`s on purpose (Probe / state write failures that must stay
  visible in Release); they are exempt from the scan, not an invitation to add more.

## Debugging Map

- Build/setup failures: `Package.swift`, `Makefile`, `scripts/preflight-check.sh`,
  `scripts/build-syphon.sh`.
- Missing public API in AI docs: `Makefile` `symbol-graphs`, then
  `scripts/generate-llms-txt.py` (its inclusion rules are pinned by
  `scripts/tests/test_generate_llms_txt.py`), then regenerate `llms.txt`.
- Sketch lifecycle or input bugs: `SketchRunner.swift`, `SketchContext.swift`,
  `InputManager.swift`, `MetaphorRenderer.swift`.
- 2D drawing bugs: start at the relevant `Sketch+*.swift` wrapper, then
  `SketchContext+*.swift`, then `Canvas2D*.swift`.
- 3D drawing bugs: `Sketch+3D.swift`, `SketchContext+3D.swift`, `Canvas3D*.swift`
  (split by concern: `+Frame`, `+Recording`, `+Primitives`, `+Shapes`,
  `+ShapeDrawing`, `+MeshDrawing`), `Mesh.swift`, `PipelineFactory.swift`,
  shader files.
- 2D drawn *after* a 3D object shows up *behind* it, or a sketch looks different
  with `METAPHOR_COMMAND_RECORD=1`: the immediate path fixes z-order when a 2D
  batch is **flushed**, not when the call is made, so 2D that overlaps 3D must sit
  in the last batch of the frame. Batches flush early on a `blendMode()` change,
  on alternating with `image()` / `text()` (textured vertices) or `circles()`
  (instancing), on `beginClip()` / `endClip()`, on `loadPixels()` (the same-frame
  readback splits the main pass), and when the vertex buffer cannot
  grow — `Canvas2D.blendMode(_:)`, `Canvas2DVertexWriter.addVertex`,
  `Canvas2D+Clipping.swift`, `SketchContext+Pixels.swift`. The record path (shadows
  on, or the opt-in) replays in
  call order via `Canvas3D.flushPending2D`, so the paths disagree exactly here.
  Conditions and measurements: the 2026-08-16 and 2026-08-18 notes under the
  Amendment in [ADR-0003](../adr/0003-unified-command-stream.md).
  Note that the split point itself must flush in the *same order as* `endFrame()`
  (`canvas3D.end()` → `canvas.end()`, i.e. 3D then 2D); flushing 2D first there
  put pre-split 2D behind pre-split 3D (#832, fixed).
- Shader failures: keep `Shaders/Metal/*.metal`, `Shaders/ShaderSources/*.txt`,
  and shader function constants in sync.
- Export/readback bugs: `FrameExporter.swift`, `VideoExporter.swift`,
  `GIFExporter.swift`, `RenderTestHelper.swift`.
- Observability (Probe / input injection) runtime cost: `MetaphorProbePlugin.swift`,
  `InputInjectionPlugin.swift`, plugin dispatch in `MetaphorRenderer.swift`,
  `MetaphorRenderer.probePlugin` cache used by `Sketch+Probe.swift`.
- `@Param` not persisting / external writes ignored: `Parameters/ParameterPlugin.swift`
  (mtime polling of `set-request.json`, debounced write of `params.json`),
  `Parameters/ParameterStore.swift` (Mirror discovery, type/range/choices checks),
  `Parameters/ParamValue.swift` (JSON ⇄ typed value). Rejected writes are reported in
  `params.json`'s `warnings[]`; `METAPHOR_DEBUG=1` adds stderr diagnostics.
  Note that `JSONSerialization` returns numbers and booleans alike as `NSNumber`,
  and Swift's `is Bool` is true for the numbers 0 and 1 — type checks here must use
  `CFBooleanGetTypeID`, or `[1, 0.5, 0.25, 1]` silently stops being a color.
- `gui.params()` panel misplaced / a widget overlapping the next one:
  `UI/ParameterGUI+Params.swift`. The panel background is drawn *before* the
  widgets from `rowHeight(for:)`, so that single-frame captures are correct; that
  one table is the layout canon and every row is snapped to it. A widget whose
  drawing advances `currentY` differently from the table will overlap — the
  "layout table matches widgets" test in `ParameterGUITests.swift` guards this.
  The GUI never stores values: it reads `ParameterStore` and writes back through
  `setValue` only when a value actually changed (otherwise `revision` would climb
  every frame and `params.json` would be rewritten forever).

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
- `SketchContext.loadPixels()` is the one deliberate mid-frame CPU/GPU sync
  point (ADR-0005 Decision 6, #326). Called inside `draw()`, it splits the main
  render pass: flush the pending 2D/3D batches, end the encoder, ride the
  readback blit on the frame's own command buffer, commit, `waitUntilCompleted`,
  then continue in a `loadAction = .load` pass and rebind both canvases to the
  new encoder (`MetaphorRenderer.splitMainPassForReadback`). Two properties must
  hold when touching this: the split is **invisible in the output** (the
  continuation must load, not clear, the color attachment — guarded by
  `CanvasPixelsTests`), and it costs **nothing** for sketches that never call
  `loadPixels()`. Depth is not preserved across the split (the main pass stores
  `.dontCare`), and the shadow record/replay path (#70) cannot split at all and
  falls back to the last committed frame.
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
  `ParameterPlugin` follows the same shape: it is only registered when the sketch
  declares at least one `@Param`, and its per-frame cost is one `stat()` of
  `set-request.json` plus a revision comparison; encoding happens on the main
  thread only when a value changed, disk I/O on a dedicated serial queue.

## Verification

- Run `make ai-docs-check` after changing AI-facing docs, module lists, or
  version snippets.
- Run `make llms-txt` after public API edits.
- Run focused Swift tests with `swift test --filter <SuiteOrTestName>` while
  iterating, then `make test` before handing off broader changes.
- Run `make ci-check` before pushing — it is `make build` + `make test` with
  CI's `-Xswiftc -warnings-as-errors`. Plain `make build` / `make test` let
  warnings pass, so a locally green branch can still fail CI (see
  DEVELOPMENT.md, "push 前は `make ci-check`").
- For rendering behavior, prefer pixel/readback tests via `MetaphorTestSupport`
  over visual-only examples.

## ゴールデンイメージ回帰 (Issue #330)

代表シーンのフレームバッファ全体を PNG で固定し、意図しない見た目の変化を検出する。

- **テスト**: `Tests/metaphorTests/GoldenImageTests.swift`
- **ゴールデン**: `Tests/metaphorTests/Golden/*.png`（リポジトリにコミット。ソースツリーを
  直接読み書きするので、更新差分がそのまま `git diff` に出る）
- **ヘルパー**: `Sources/MetaphorTestSupport/GoldenImage.swift`
  （SHA256・閾値つき比較・PNG 入出力・GPU 読み戻し・差分画像）
- **シーン**: 2D 図形 / α 合成 / ブレンドモード / 3D ライティング (Blinn-Phong・PBR) /
  シャドウ / ポストプロセス。各シーンは 2 回レンダリングしてハッシュ一致
  （同一環境での決定論）も同時に検証する。

### 半透明（α < 1）を含むシーンについて

**ゴールデンは非不透明画素を含んでよい**（`alpha-compositing` がそれ）。以前は
「PNG 往復が非可逆だから不透明であること」を `verify()` が要求していたが、非可逆
だったのは `GoldenImage.rgba`（straight）を `premultipliedLast` と宣言して書いて
いたためで、ImageIO が PNG（straight）へ書くときに α で割って飽和させていた
（α=128 の白で誤差 127）。straight を `CGImageAlphaInfo.last` として書き、
読みは生サンプルを採るようにして、**α の全域で往復がバイト一致する**（#850）。
α = 255 では両者が同値なので、この修正で既存のゴールデン PNG は 1 バイトも変わっていない。

### 判定方式

合否は **閾値つきピクセル比較**（`GoldenTolerance`）で決める。SHA256 は同一環境での
再現性の測定とログ出力にのみ使い、合否には使わない。

- `.default`（2D 系）: チャンネル差 <= 2 を許容、超過ピクセルは 0 個まで
- `.shaded`（ライティング / シャドウ / ポストプロセス）: チャンネル差 <= 4 を許容、
  超過ピクセルは全体の 0.2% まで

実測（Issue #330、GitHub Actions の macOS ランナー vs 手元の Apple Silicon）:
6 シーン中 5 シーンが **バイト単位で一致**（SHA256 も一致）。差が出たのは PBR
シーンのみで、16384 画素中 **1 画素が 1/255 ずれる**だけだった。つまり現状の
許容差は「今まさに必要な緩さ」ではなく安全余裕であり、GPU 世代が増えたときの
保険として置いてある。

それでもハッシュ完全一致を合否条件にしないのは、環境が 1 つでもズレた時点で
「環境ごとにゴールデンを持つ」しかなくなり、意図した見た目変更のたびに全環境ぶんの
更新が必要になって保守が破綻するため。各テストは実行のたびに `[golden] <name> vs
golden: maxChannelDiff=...` を出力するので、環境差が広がっていないかはログで追える。

### 意図した見た目変更時の更新手順

1. `METAPHOR_UPDATE_GOLDEN=1 swift test --filter GoldenImageTests` でゴールデンを再生成
2. `git diff` に出た PNG を**目視で確認**する（差分が意図どおりか）
3. 変更理由を PR 本文に書いてコミットする

新しいシーンを足す場合はゴールデンが存在しないので、初回実行で自動生成されつつ
テストは**失敗する**（レビュー無しに緑にしないため）。生成された PNG を確認して
コミットし、もう一度実行して緑を確認する。

### 落ちたときの調べ方

失敗すると `.build/golden-failures/<name>.{actual,expected,diff}.png` が書き出される
（`METAPHOR_GOLDEN_ARTIFACT_DIR` で出力先を変更可）。CI では `golden-image-failures`
アーティファクトとしてアップロードされるので、ダウンロードして diff 画像を見れば
どの領域が変わったかがすぐ分かる。

### テキストを対象にしない理由

グリフのラスタライズは OS のフォントスタックに依存し、macOS のマイナー更新でも
画素が変わり得る。ゴールデンに入れると「ライブラリの退行」と「OS 更新」を区別
できなくなるため、テキストは `GlyphAtlasTests` / `DrawingTests` の構造的な検証に委ねる。
