# CLAUDE.md

> NOTE: `AGENTS.md` はこのファイルのコピー（タイトル行のみ異なる）です。
> こちらを変更したら `AGENTS.md` も同じ内容に更新してください。

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

For full API details, see `llms.txt` (auto-generated via `make llms-txt`).

| Category | Key Functions | Source |
|----------|--------------|--------|
| 2D Shapes | circle, rect, ellipse, line, triangle, arc, bezier, polygon | Sketch+Shapes.swift |
| 3D Shapes | box, sphere, plane, cylinder, cone, torus, mesh, loadModel | Sketch+3D.swift |
| Style | fill, stroke, strokeWeight, blendMode, background, tint | Sketch+Style.swift |
| Transform | translate, rotate, scale, push/pop | Sketch+Shapes.swift |
| Camera | camera, perspective, ortho, orbitControl | Sketch+3D.swift, Sketch+Advanced.swift (orbitControl) |
| Lighting | lights, directionalLight, pointLight, spotLight | Sketch+3D.swift |
| Material | specular, metallic, roughness, pbr, createMaterial | Sketch+3D.swift |
| Image | loadImage, image, createGraphics, createCapture | Sketch+Image.swift |
| Text | text, textSize, textFont, textAlign | Sketch+Image.swift |
| Pixels | loadPixels, updatePixels, pixels | Sketch+Pixels.swift |
| Compute | createComputeKernel, createBuffer, dispatch | Sketch+Advanced.swift |
| Particles | createParticleSystem, updateParticles, drawParticles | Sketch+Advanced.swift |
| PostFX | addPostEffect, createPostEffect, BloomEffect, BlurEffect | Sketch+Advanced.swift |
| Export | save, beginVideoRecord, beginGIFRecord, beginRecord | Sketch+Image.swift, Sketch+Advanced.swift (GIF) |
| Audio | createAudioInput, loadSound | Sketch+AudioBridge.swift |
| Video | loadVideo, image(video) | Sketch+VideoBridge.swift |
| Physics | createPhysics2D | Sketch+PhysicsBridge.swift |
| Network | createOSCReceiver, createMIDI | Sketch+NetworkBridge.swift |
| Noise | createNoise, noiseTexture, noise() | Sketch+NoiseBridge.swift, Noise.swift (noise()) |
| SceneGraph | createNode, drawScene | Sketch+SceneGraphBridge.swift |
| RenderGraph | createSourcePass, createEffectPass, createMergePass | Sketch+RenderGraphBridge.swift |
| Probe (AI) | probe(name, value), MetaphorProbePlugin | Sketch+Probe.swift |

## AI Probe

`MetaphorProbePlugin` を有効化するとスケッチが「いま見えている画像」と「内部状態」を AI エージェントに渡せる。

- 有効化: 環境変数 `METAPHOR_PROBE=1` で自動登録、または `SketchConfig(plugins: [PluginFactory { MetaphorProbePlugin() }])` で明示登録。
- リクエスト: AI 側が `.metaphor/probe/request.json` を `{"id":"snap-1","label":"baseline"}` で書き込む。次フレームで処理される（id を変えるたびに 1 回だけ走る）。
- 出力: `.metaphor/probe/current/frame.png` と `frame.json`。書き込みは `.tmp` 経由の atomic rename。
- 状態の申告: スケッチの `draw()` の中で `probe("particles.count", n)` のように呼ぶ。プラグイン未登録時は no-op。
- 警告: 32x32 サンプルで色分散を測り、blank フレームを `frame.json.warnings` に出す。
- 通常時はリクエストファイルの mtime を見るだけなのでホットパスは触らない。
- サンプル: `Examples/Samples/ProbeSnapshot`

## Conventions

- macOS 14.0+ (Apple Silicon), Swift 5.10+
- Uses Swift Testing framework (`@Suite`, `@Test`), not XCTest
- New examples should follow existing directory structure: `Examples/{Category}/{Subcategory}/{Name}/`
- Each example is an independent SPM package with its own `Package.swift`

## Branching Workflow (GitHub Flow)

- **`main`** — the only long-lived branch. All work flows back here via PR. Protected by ruleset: PR required, `build-and-test` must pass, admin can bypass for emergencies.
- Feature branches off `main` are short-lived and auto-deleted on merge.
- Repository merge settings: **squash merge only**, auto-delete branch on merge.
- CI fires on `push: main`, `pull_request: main`, and `workflow_dispatch` (the Release workflow uses workflow_dispatch to re-enter CI on release branches).

### When to branch (Claude default)

Create a branch off `main` for any **non-trivial** work — new features, bug fixes that touch more than a line or two, refactors, anything that produces multiple commits. Don't push directly to main. The ruleset blocks it for non-admins anyway.

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
git checkout main && git pull
git checkout -b feature/<name>
# ... implement ...
git push -u origin feature/<name>
gh pr create --base main --title "..." --body "..."
# wait for CI
gh pr merge --squash --delete-branch
git checkout main && git pull
```

### Notes for Claude

- Default to creating a branch off `main` for any non-trivial change. Trivial edits (typo, 1-line config) may go directly to `main` only via PR (the ruleset enforces this for non-admins).
- Squash merge is the only allowed style — write one good final commit message in the PR title/body; per-commit messages on the branch are throwaway.
- After merge, switch back to `main` and pull. Local feature branches can be pruned with `git fetch -p`.

## Releases

Releases go through a single `workflow_dispatch` trigger on the `Release` workflow. No PAT required — the workflow re-enters CI on its own release branch using `workflow_dispatch` (which is exempt from the GITHUB_TOKEN recursion guard).

### Inputs

| Input | Purpose |
|-------|---------|
| `bump` | `patch` / `minor` / `major` / `prerelease` |
| `prerelease_label` | `beta`, `rc`, etc. Empty for stable. Ignored when `bump=prerelease`. |

### Common operations

| Goal | Inputs | Resulting tag |
|------|--------|---------------|
| Stable patch | `bump=patch`, label empty | `v0.2.4` |
| Start a beta cycle | `bump=minor`, `label=beta` | `v0.3.0-beta.1` |
| Iterate the beta | `bump=prerelease` | `v0.3.0-beta.2` |
| Promote to RC | `bump=minor`, `label=rc` | `v0.3.0-rc.1` |
| Graduate to stable | `bump=minor`, label empty | `v0.3.0` |

Pre-release tags (anything containing `-`) are automatically marked as Pre-release on GitHub. Package.swift `from:` example in README is only updated for stable releases.
