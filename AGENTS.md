# AGENTS.md

> NOTE: `AGENTS.md` は `CLAUDE.md` から生成されるコピーです（タイトル行のみ異なる）。
> `CLAUDE.md` を編集し、`make docs-sync` を実行して同期してください（CI で同期を検証します）。

## Build Commands

```bash
make setup           # First-time setup: init submodules + build Syphon.xcframework
make build           # Build the library (swift build)
make test            # Run tests (swift test)
make clean           # Clean build artifacts
make check           # Verify setup status (Syphon.xcframework, submodules)
make llms-txt        # Generate llms.txt (AI-readable API reference)
make examples-index  # Generate docs/ai/examples-index.{md,json}
```

For examples:
```bash
cd Examples/Basics/Form/ShapePrimitives && swift build && swift run
```

For deeper AI-oriented debugging and extension notes, see `docs/ai/README.md`.

### Generated AI-facing files

`llms.txt` and `docs/ai/examples-index.{md,json}` are checked in but
**auto-generated** — never hand-edit them. Their inputs are:

| Output | Inputs |
|---|---|
| `llms.txt` | `Sources/**/*.swift`, `scripts/generate-llms-txt.py` |
| `docs/ai/examples-index.{md,json}` | `Examples/**`, `scripts/generate-examples-index.py` |

If you change any input, regenerate before pushing (`make llms-txt` or
`make examples-index`). The pre-push hook installed by `make setup`
checks this and aborts otherwise. CI also auto-regenerates the examples
index for PRs from this repo as a safety net.

Generators MUST be deterministic (no wall-clock timestamps, sort all
collections) — non-determinism causes the auto-fix bot to push every
run forever.

## Architecture Overview

metaphor is a Swift + Metal creative coding library inspired by Processing. It provides a `Sketch` protocol for declarative frame-based rendering, with 2D/3D drawing, GPU compute, post-processing, physics, audio, and more. macOS (Apple Silicon) only.

### Module Structure

Multi-target SPM architecture. `import metaphor` (umbrella, re-exports all via `@_exported import`) or import individual modules:

- **Tier 1 (no Core dependency)**: MetaphorAudio, MetaphorNetwork, MetaphorPhysics, MetaphorML, MetaphorVideo
- **Tier 2 (depends on MetaphorCore)**: MetaphorNoise, MetaphorMPS, MetaphorCoreImage, MetaphorRenderGraph, MetaphorSceneGraph

The umbrella target provides bridge extensions (`Sketch+AudioBridge.swift`, etc.) so `import metaphor` users get convenience methods like `createAudioInput()`, `createOSCReceiver()`, `createPhysics2D()`.

### 3-Layer API Architecture

```
Sketch protocol extensions  ← User-facing (Processing-like globals via _activeSketchContext)
        ↓
   SketchContext             ← Bridges Sketch to Canvas2D/Canvas3D
        ↓
  Canvas2D / Canvas3D        ← Low-level Metal rendering
```

### Rendering Pipeline

Two-pass system:

1. **Offscreen Pass**: Compute phase → MTLEvent barrier → Draw phase → Shadow pass → RenderGraph → PostProcess → Export/Syphon
2. **Blit Pass**: Blits offscreen texture to screen with aspect ratio preservation (letterbox/pillarbox)

This decouples rendering resolution from window size and enables Syphon output at fixed resolution.

### Key Design Patterns

- **GPU Instancing**: Canvas2D/Canvas3D auto-batch consecutive same-shape draws via `InstanceBatcher<T>`
- **Triple-buffered GPU buffers**: Vertex, instance, and `GrowableGPUBuffer` use semaphore value 3
- **Dual pipeline**: Untextured (positionNormalColor) + textured (positionNormalUV), each with instanced variants
- **PBR + Blinn-Phong**: Material3D auto-switches based on `usePBR` flag (single shader, conditional)
- **Shadow mapping**: DrawCall recording → depth-only shadow pass → PCF 3x3 filtering
- **Shader hot reload**: ShaderLibrary supports runtime MSL reloading for CustomMaterial/CustomPostEffect
- **Compute→Render sync**: `MTLEvent` for explicit barriers between compute and render passes
- **RenderLoopMode**: DisplayLink (default) or DispatchSourceTimer for Syphon/export
- **Plugin protocol**: `MetaphorPlugin` provides lifecycle hooks (onBeforeRender, onAfterRender, onResize, etc.)

### Syphon Framework Handling

- **Local dev**: Package.swift uses `Frameworks/Syphon.xcframework` if present (built by `make setup`)
- **SPM users**: Falls back to downloading pre-built XCFramework from GitHub Releases

### API Quick Map

For API signatures, see `llms.txt` (auto-generated via `make llms-txt`). It
lists every function but **not** which file implements it — this maps a feature
area to its source so you know where to edit:

- **2D shapes, transform** (circle, rect, line, arc, bezier, push/pop): `Sketch+Shapes.swift`
- **3D** (box, sphere, camera, perspective, lights, material, pbr): `Sketch+3D.swift`
- **Style** (fill, stroke, strokeWeight, blendMode, tint): `Sketch+Style.swift`
- **Image, text, export** (loadImage, text, save, beginVideoRecord): `Sketch+Image.swift`
- **Pixels** (loadPixels, updatePixels): `Sketch+Pixels.swift`
- **Compute, particles, postFX, GIF, orbitControl**: `Sketch+Advanced.swift`
- **Bridges** — audio/video/physics/network/noise/scene/render graph: `Sketch+*Bridge.swift` (e.g. `createAudioInput` → `Sketch+AudioBridge.swift`)
- **Probe (AI)** (probe, MetaphorProbePlugin): `Sketch+Probe.swift`
- **noise()** standalone: `Noise.swift`

## AI Probe

`MetaphorProbePlugin` を有効化するとスケッチが「いま見えている画像」と「内部状態」を AI エージェントに渡せる。

- 有効化: 環境変数 `METAPHOR_PROBE=1` で自動登録、または `SketchConfig(plugins: [PluginFactory { MetaphorProbePlugin() }])` で明示登録。
- リクエスト: AI 側が `.metaphor/probe/request.json` を `{"id":"snap-1","label":"baseline"}` で書き込む。次フレームで処理される（id を変えるたびに 1 回だけ走る）。
- 出力: `.metaphor/probe/current/frame.png` と `frame.json`。書き込みは `.tmp` 経由の atomic rename。
- 状態の申告: スケッチの `draw()` の中で `probe("particles.count", n)` のように呼ぶ。プラグイン未登録時は no-op。
- 警告: 32x32 サンプルで色分散を測り、blank フレームを `frame.json.warnings` に出す。
- 通常時はリクエストファイルの mtime を見るだけなのでホットパスは触らない。
- サンプル: `Examples/Samples/ProbeSnapshot`

## Cross-Repo Contract (metaphor ⇄ metaphor-cli)

`metaphor-cli`（別リポジトリ `shinyaoguri/metaphor-cli`）はこのリポジトリを
Swift ライブラリとしては依存していないが、**ランタイム/バイナリの暗黙の契約**
で結合している（環境変数・stdin JSON Lines 入力・Probe ファイル・Syphon の
Release pin）。完全な一覧と変更ルールは **[CONTRACT.md](CONTRACT.md)** を参照。

**重要（エージェント向け）**: 以下に触れる変更は `metaphor` 単体では完結しない。
必ず `metaphor-cli` 側も同時に更新し、両リポジトリの `CONTRACT.md` を揃え、
`./scripts/check-contract.sh` が緑であることを確認すること。片方だけ作業中なら
もう片方に対応 PR/Issue を必ず立てる。

- 環境変数 `METAPHOR_VIEWER` / `METAPHOR_SYPHON_NAME` / `METAPHOR_FPS` / `METAPHOR_PROBE`（`SketchRunner.swift`）
- stdin 入力イベントのキー/値（`InputInjectionPlugin.swift`：`mouseDown` 等）
- Probe のパス/スキーマ（`MetaphorProbeConfig.swift` / `ProbeFrameMetadata.swift`）
- Syphon.xcframework の Release 発行（`release.yml`、cli の `Package.swift` が pin）

CI は `scripts/check-contract.sh` で契約トークンの消失を検知する。

## Conventions

- macOS 14.0+ (Apple Silicon), Swift 5.10+
- Uses Swift Testing framework (`@Suite`, `@Test`), not XCTest
- New examples should follow existing directory structure: `Examples/{Category}/{Subcategory}/{Name}/`
- Each example is an independent SPM package with its own `Package.swift`

## Branching Workflow (GitHub Flow)

- **`main`** — the only long-lived branch and the default branch. All work flows
  back here via PR. Protected by ruleset: PR required, `build-and-test` must pass,
  direct push forbidden (deletion / non-fast-forward blocked), **squash-only**.
- Feature branches off `main` are short-lived and auto-deleted on merge.
- CI fires on `push: main`, `pull_request: main`, and `workflow_dispatch` (the
  Release workflow re-enters CI on `release/<tag>` branches via workflow_dispatch).

### Releasing

Releases are driven by a `release:*` label on a PR (`release:patch` /
`release:minor` / `release:major`), not by a separate branch — merge the
labeled PR (squash) and the **Release** workflow tags and publishes both
metaphor and metaphor-cli. An unlabeled PR does **not** release. Full procedure,
manual `workflow_dispatch` inputs, and version-bump operations:
**[docs/releasing.md](docs/releasing.md)**.

### When to branch (Claude default)

Create a branch off `main` for any **non-trivial** work — new features, bug fixes
beyond a line or two, refactors, anything multi-commit. Don't push directly to
`main`; the ruleset blocks it.

### Naming

Use kebab-case with a category prefix:
- `feature/<short-name>` — new public API, new module, new example
- `fix/<short-name>` — bug fix
- `refactor/<short-name>` — internal restructuring with no API change
- `chore/<short-name>` — tooling, CI, build scripts
- `docs/<short-name>` — documentation-only
- `release/<tag>` — reserved for the Release workflow; do not reuse

### Standard flow

```bash
git checkout -b feature/<name>          # off main; see Naming above
gh pr create --base main                # add --label release:minor to ship a release
gh pr merge --squash --delete-branch    # squash-only, auto-delete branch
```

General git hygiene (Conventional Commits, one concern per commit, push only
when asked) lives in the global CLAUDE.md — not repeated here.

### Notes for Claude

- All PRs target `main`. A release is driven by a `release:*` label on the PR.
- Squash merge is the only allowed style — write one good final commit message in
  the PR title/body; per-commit messages on the branch are throwaway.
- After merge, switch back to `main` and pull. Prune local branches with `git fetch -p`.
