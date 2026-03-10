# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
make setup           # First-time setup: init submodules + build Syphon.xcframework
make build           # Build the library (swift build)
make test            # Run tests (swift test)
make test-verbose    # Run tests with verbose output
make test-coverage   # Run tests and display coverage report
make test-lcov       # Generate LCOV coverage data for CI integration
make release         # Build release version (optimized)
make clean           # Clean build artifacts
make clean-all       # Full clean including submodules
make check           # Verify setup status (Syphon.xcframework, submodules)
make docs            # Build DocC documentation with symbol graph extraction
make docs-preview    # Preview DocC documentation locally
make examples        # Run examples in parallel (10 workers, excludes _Legacy/)
make examples-seq    # Run examples sequentially (interactive)
make examples-check  # Build-only verification of all examples (parallel)
make examples-list   # List all available examples
make help            # Display help message
```

For examples:
```bash
cd Examples/Basics/Form/ShapePrimitives && swift build && swift run
cd Examples/Topics/Simulate/ParticleSystem && swift build && swift run
```

## Architecture Overview

metaphor is a Swift + Metal creative coding library inspired by Processing/p5.js/openFrameworks. It provides a `Sketch` protocol for declarative frame-based rendering, with 2D/3D drawing, GPU compute, post-processing, physics, audio, and more. macOS (Apple Silicon) only.

### Module Structure

metaphor uses a multi-target SPM architecture. Users can `import metaphor` for full functionality (backward compatible) or import individual modules:

| Module | Purpose | Dependencies |
|--------|---------|-------------|
| `metaphor` | Umbrella target — re-exports all modules via `@_exported import` | All modules |
| `MetaphorCore` | Core rendering engine, drawing, shaders, Sketch protocol | Syphon |
| `MetaphorAudio` | Audio analysis (FFT, beat detection) and sound file playback | None (Tier 1) |
| `MetaphorNetwork` | OSC receiver (UDP) and MIDI manager | None (Tier 1) |
| `MetaphorPhysics` | 2D physics simulation with Verlet integration | None (Tier 1) |
| `MetaphorML` | CoreML texture conversion (Metal ↔ CVPixelBuffer ↔ CGImage) | None (Tier 1) |
| `MetaphorNoise` | Perlin/Simplex noise generation, NoiseTexture | MetaphorCore (Tier 2) |
| `MetaphorMPS` | Metal Performance Shaders (image filters, ray tracing) | MetaphorCore (Tier 2) |
| `MetaphorCoreImage` | Core Image integration (zero-copy Metal interop, 30+ presets) | MetaphorCore (Tier 2) |
| `MetaphorRenderGraph` | DAG-based multi-pass rendering (SourcePass, EffectPass, MergePass) | MetaphorCore (Tier 2) |
| `MetaphorSceneGraph` | Node hierarchy, frustum culling, SceneRenderer | MetaphorCore (Tier 2) |
| `MetaphorTestSupport` | Internal test utilities (not published) | MetaphorCore |

The umbrella `metaphor` target provides bridge extensions (`Sketch+AudioBridge.swift`, `Sketch+NoiseBridge.swift`, etc.) so that `import metaphor` users retain convenience methods like `createAudioInput()`, `createOSCReceiver()`, `createPhysics2D()`.

### Rendering Pipeline

The rendering uses a **two-pass system**:

1. **Offscreen Pass**: Sketch draws to TextureManager's offscreen textures (color + depth) via Canvas2D/Canvas3D
   - Compute phase → MTLEvent barrier → Draw phase → Shadow pass → RenderGraph → PostProcess → Export/Syphon
2. **Blit Pass**: Built-in pipeline blits offscreen texture to screen with aspect ratio preservation (letterbox/pillarbox)

This decouples rendering resolution from window size and enables Syphon output at fixed resolution.

### Typical Usage (Sketch Protocol)

```swift
import metaphor

@main
final class MySketch: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "My Sketch", width: 1920, height: 1080)
    }

    func setup() {
        // One-time initialization
    }

    func draw() {
        background(.black)
        fill(.white)
        circle(width / 2, height / 2, 200)
    }
}
```

The `Sketch` protocol provides Processing-like global functions (`background`, `fill`, `circle`, `rect`, etc.) via a global `_activeSketchContext`. Users implement `draw()` (called every frame) and optionally `setup()`, `compute()`, and input event handlers (`mousePressed`, `keyPressed`, etc.).

### 3-Layer API Architecture

```
Sketch protocol extensions  ← User-facing (Processing-like globals)
        ↓
   SketchContext             ← Bridges Sketch to Canvas2D/Canvas3D
        ↓
  Canvas2D / Canvas3D        ← Low-level Metal rendering
```

- **Sketch** (`Sketch/Sketch.swift`): Protocol with default implementations. Forwards calls to `_activeSketchContext`.
- **SketchContext** (`Sketch/SketchContext.swift`): Holds Canvas2D, Canvas3D, renderer, input, time state. Provides all drawing methods.
- **SketchRunner** (`Sketch/SketchRunner.swift`): NSApplicationDelegate that creates window, MTKView, renderer, and drives the frame loop.

### Core Components (Sources/MetaphorCore/)

| Directory | Purpose |
|-----------|---------|
| `Core/` | MetaphorRenderer (orchestrator), TextureManager, PipelineFactory, ShaderLibrary, ResourceLoader, MetaphorPlugin protocol, RenderLoopMode, SharedMetalResources |
| `Drawing/` | Canvas2D (2D vector), Canvas3D (3D meshes/lights/materials), InstanceBatcher, GrowableGPUBuffer, CustomMaterial, ShadowMap, TextRenderer, MImage, MShape |
| `Shaders/` | Swift shader wrappers + `Metal/` compiled .metal files + `ShaderSources/` hot-reload .txt files |
| `Sketch/` | Sketch protocol (+ extensions: 3D, Shape, Style, Image, Pixels, Window, Advanced), SketchContext (+ extensions), SketchRunner, SketchWindow |
| `Geometry/` | Mesh primitives, DynamicMesh, EarClipTriangulator, ModelIOLoader (OBJ/USDZ) |
| `PostProcess/` | PostProcessPipeline, PostEffect enum, CustomPostEffect |
| `Compute/` | ComputeKernel, GPUBuffer\<T\>, ImageFilterGPU |
| `Particle/` | ParticleSystem (GPU compute + instanced billboard) |
| `Animation/` | Tween\<T\>, TweenManager |
| `Export/` | VideoExporter (H.264), GIFExporter, FrameExporter |
| `Input/` | InputManager (mouse/keyboard), CaptureDevice (camera) |
| `UI/` | MetaphorView (SwiftUI), MetaphorMTKView, SketchView, ParameterGUI, PerformanceHUD, OrbitCamera |
| `Utilities/` | Math (float4x4), Time (FrameTimer), Easing (30 functions), Color, Vector, Noise, Platform, Log, Constants |
| `Syphon/` | SyphonOutput (inter-app video sharing) |

### Standalone Modules

| Module | Directory | Key Files |
|--------|-----------|-----------|
| MetaphorAudio | `Sources/MetaphorAudio/` | AudioAnalyzer.swift, SoundFile.swift |
| MetaphorNetwork | `Sources/MetaphorNetwork/` | OSCReceiver.swift, MIDIManager.swift, MIDIMessage.swift |
| MetaphorPhysics | `Sources/MetaphorPhysics/` | Physics2D.swift, PhysicsBody2D.swift, PhysicsConstraint2D.swift, SpatialHash2D.swift |
| MetaphorML | `Sources/MetaphorML/` | MLTextureConverter.swift |
| MetaphorNoise | `Sources/MetaphorNoise/` | GKNoiseGenerator.swift, NoiseTexture.swift, NoiseType.swift |
| MetaphorMPS | `Sources/MetaphorMPS/` | MPSImageFilter.swift, MPSRayTracer.swift, MPSRayScene.swift, MPSEffects.swift |
| MetaphorCoreImage | `Sources/MetaphorCoreImage/` | CIFilterWrapper.swift, CIFilterPreset.swift, CIEffects.swift |
| MetaphorRenderGraph | `Sources/MetaphorRenderGraph/` | RenderGraph.swift, RenderPassNode.swift, SourcePass.swift, EffectPass.swift, MergePass.swift |
| MetaphorSceneGraph | `Sources/MetaphorSceneGraph/` | Node.swift, SceneRenderer.swift |
| MetaphorTestSupport | `Sources/MetaphorTestSupport/` | RenderTestHelper.swift, MetalTestHelper.swift, TempFileHelper.swift, Assertions.swift |

### Key Design Patterns

- **GPU Instancing**: Both Canvas2D and Canvas3D auto-batch consecutive same-shape draws into instanced draw calls via generic `InstanceBatcher<T>`
- **Triple-buffered GPU buffers**: Vertex, instance, and `GrowableGPUBuffer` data use triple buffering (semaphore value 3) for CPU/GPU overlap
- **Dual pipeline**: Untextured (positionNormalColor) + textured (positionNormalUV) shader paths, each with instanced variants
- **PBR + Blinn-Phong**: Material3D auto-switches between PBR and Blinn-Phong based on `usePBR` flag (single shader, conditional)
- **Shadow mapping**: DrawCall recording → depth-only shadow pass → PCF 3x3 filtering
- **Shader hot reload**: ShaderLibrary supports runtime MSL reloading for CustomMaterial/CustomPostEffect
- **Compute→Render sync**: `MTLEvent` for explicit barriers between compute and render passes
- **RenderLoopMode**: DisplayLink (default) or independent DispatchSourceTimer for Syphon/export use cases
- **Plugin protocol**: `MetaphorPlugin` provides lifecycle hooks (onBeforeRender, onAfterRender, onResize, etc.) for extending the render loop
- **Async resource loading**: `ResourceLoader` for off-main-thread image/model loading via MTKTextureLoader
- **Modular architecture**: Tier 1 modules (Audio, Network, Physics, ML) have zero Core dependency; Tier 2 modules (Noise, MPS, CoreImage, RenderGraph, SceneGraph) depend on MetaphorCore; umbrella target re-exports all
- **macOS only**: All code targets macOS (Apple Silicon); no iOS conditional compilation

### Syphon Framework Handling

- **Local dev**: Package.swift uses `Frameworks/Syphon.xcframework` if present (built by `make setup`)
- **SPM users**: Falls back to downloading pre-built XCFramework from GitHub Releases

## Requirements

- macOS 14.0+ (Apple Silicon)
- Swift 6.0+
- Xcode 15.0+

## Testing

~890 tests across 10 test targets. Uses Swift Testing framework (`@Suite`, `@Test`). Run with `make test` or `swift test`.

| Test Target | Tests | Description |
|-------------|-------|-------------|
| `metaphorTests` | ~566 | Core integration tests (Canvas2D, Canvas3D, Compute, PostProcess, Math, Shapes, etc.) |
| `MetaphorAudioTests` | ~12 | AudioAnalyzer, SoundFile tests |
| `MetaphorNetworkTests` | ~28 | OSC parser/receiver, MIDI message/manager tests |
| `MetaphorPhysicsTests` | ~20 | Physics2D basic tests |
| `MetaphorMLTests` | ~3 | ML texture conversion tests |
| `MetaphorNoiseTests` | ~26 | Noise generation tests |
| `MetaphorMPSTests` | ~22 | Metal Performance Shaders tests |
| `MetaphorCoreImageTests` | ~32 | Core Image integration tests |
| `MetaphorRenderGraphTests` | ~8 | DAG-based rendering tests |
| `MetaphorSceneGraphTests` | ~23 | Scene graph / node hierarchy tests |

## Examples

307 examples organized in 5 categories under `Examples/`:

| Category | Count | Description |
|----------|-------|-------------|
| `Basics/` | 109 | Foundational (Color, Form, Input, Math, Transform, Typography, etc.) |
| `Topics/` | 114 | Advanced (Animation, Cellular Automata, Fractals, Shaders, Simulate, etc.) |
| `Demos/` | 31 | Graphics, Performance, Tests |
| `ML/` | 4 | FaceDetection, ImageClassification, PersonSegmentation, StyleTransfer |
| `_Legacy/` | 49 | Older examples (kept for reference) |

## CI/CD

GitHub Actions workflows in `.github/workflows/`:

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | Push to main, PRs | Build + test with coverage (macOS 14, Xcode 16.2) |
| `docs.yml` | Changes to Sources/, Package.swift, website/ | DocC + Astro website → GitHub Pages |
| `release.yml` | Manual dispatch | Semantic versioning, Syphon XCFramework release, Package.swift update |
