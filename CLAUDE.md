# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
make setup      # First-time setup: init submodules + build Syphon.xcframework
make build      # Build the library (swift build)
make test       # Run tests (swift test)
make release    # Build release version
make clean      # Clean build artifacts
make check      # Verify setup status
make docs       # Build DocC documentation
```

For examples:
```bash
cd Examples/_Legacy/Basics/ShapePrimitives && swift build && swift run
cd Examples/_Legacy/Simulation/GPUParticles && swift build && swift run
```

## Architecture Overview

metaphor is a Swift + Metal creative coding library inspired by Processing/p5.js/openFrameworks. It provides a `Sketch` protocol for declarative frame-based rendering, with 2D/3D drawing, GPU compute, post-processing, physics, ML, audio, and more. Supports macOS 14+ and iOS 17+.

### Rendering Pipeline

The rendering uses a **two-pass system**:

1. **Offscreen Pass**: Sketch draws to TextureManager's offscreen textures (color + depth) via Canvas2D/Canvas3D
2. **Blit Pass**: Built-in pipeline blits offscreen texture to screen with aspect ratio preservation

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

### Core Components (Sources/metaphor/)

| Directory | Purpose |
|-----------|---------|
| `Core/` | MetaphorRenderer (orchestrator), TextureManager, PipelineFactory, ShaderLibrary |
| `Drawing/` | Canvas2D (2D vector), Canvas3D (3D meshes/lights/materials), GPU instancing, CustomMaterial, ShadowMap |
| `Shaders/` | MSL shader source (Swift wrappers) + `Metal/` compiled .metal files |
| `Sketch/` | Sketch protocol, SketchContext, SketchRunner |
| `Geometry/` | Mesh primitives, DynamicMesh, EarClipTriangulator, ModelIOLoader (OBJ/USDZ) |
| `PostProcess/` | PostProcessPipeline, PostEffect enum, CustomPostEffect |
| `Compute/` | ComputeKernel, GPUBuffer\<T\>, ImageFilterGPU |
| `Particle/` | ParticleSystem (GPU compute + instanced billboard) |
| `Animation/` | Tween\<T\>, TweenManager |
| `Audio/` | AudioAnalyzer (FFT + beat detection), SoundFile (AVAudioEngine playback) |
| `Physics/` | Physics2D world, PhysicsBody2D, constraints, SpatialHash2D |
| `ML/` | MLProcessor (CoreML), MLVision (22 VNRequest types), MLStyleTransfer |
| `MPS/` | MPSImageFilter, MPSRayTracer (AO/shadow/diffuse) |
| `CoreImage/` | CIFilterWrapper (zero-copy Metal interop), CIFilterPreset (30 filters) |
| `Noise/` | GKNoiseWrapper (8 noise types), NoiseTexture |
| `RenderGraph/` | DAG-based multi-pass rendering (SourcePass, EffectPass, MergePass) |
| `SceneGraph/` | Node hierarchy, SceneRenderer |
| `Network/` | OSCReceiver (UDP), MIDIManager (CoreMIDI) |
| `Export/` | VideoExporter (H.264), GIFExporter, FrameExporter |
| `Input/` | InputManager (mouse/keyboard/touch), CaptureDevice (camera) |
| `UI/` | MetaphorView (SwiftUI), ParameterGUI, PerformanceHUD, OrbitCamera |
| `Utilities/` | Math (float4x4), Time (FrameTimer), Easing (30 functions), Color, Vector, Platform |
| `Syphon/` | SyphonOutput (inter-app video sharing, macOS only) |

### Key Design Patterns

- **GPU Instancing**: Both Canvas2D and Canvas3D auto-batch consecutive same-shape draws into instanced draw calls
- **Triple-buffered GPU buffers**: Vertex and instance data use triple buffering for CPU/GPU overlap
- **Dual pipeline**: Untextured (positionNormalColor) + textured (positionNormalUV) shader paths
- **PBR + Blinn-Phong**: Material3D auto-switches between PBR and Blinn-Phong based on `usePBR` flag
- **Shadow mapping**: DrawCall recording → depth-only shadow pass → PCF 3x3 filtering
- **Shader hot reload**: ShaderLibrary supports runtime MSL reloading for CustomMaterial/CustomPostEffect
- **Compute lifecycle**: `onCompute(commandBuffer, time)` runs before `onDraw(renderEncoder, time)` each frame
- **Conditional compilation**: `#if os(macOS)` / `#if os(iOS)` for platform-specific code (Platform.swift type aliases)

### Syphon Framework Handling

- **Local dev**: Package.swift uses `Frameworks/Syphon.xcframework` if present (built by `make setup`)
- **SPM users**: Falls back to downloading pre-built XCFramework from GitHub Releases

## Requirements

- macOS 14.0+ / iOS 17.0+
- Swift 6.0+
- Xcode 15.0+

## Testing

~562 tests across 25 test suites in `Tests/metaphorTests/`. Tests cover all major subsystems. Run with `make test` or `swift test`.
