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

## ゴールデンイメージ回帰 (Issue #330)

代表シーンのフレームバッファ全体を PNG で固定し、意図しない見た目の変化を検出する。

- **テスト**: `Tests/metaphorTests/GoldenImageTests.swift`
- **ゴールデン**: `Tests/metaphorTests/Golden/*.png`（リポジトリにコミット。ソースツリーを
  直接読み書きするので、更新差分がそのまま `git diff` に出る）
- **ヘルパー**: `Sources/MetaphorTestSupport/GoldenImage.swift`
  （SHA256・閾値つき比較・PNG 入出力・GPU 読み戻し・差分画像）
- **シーン**: 2D 図形 / ブレンドモード / 3D ライティング (Blinn-Phong・PBR) /
  シャドウ / ポストプロセス。各シーンは 2 回レンダリングしてハッシュ一致
  （同一環境での決定論）も同時に検証する。

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
