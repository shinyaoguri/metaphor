# CLAUDE.md

## Build Commands

```bash
make setup           # First-time setup: init submodules + build Syphon.xcframework
make build           # Build the library (swift build)
make test            # Run tests (swift test)
make clean           # Clean build artifacts
make check           # Verify setup status (Syphon.xcframework, submodules)
```

For examples:
```bash
cd Examples/Basics/Form/ShapePrimitives && swift build && swift run
```

## Architecture Overview

metaphor is a Swift + Metal creative coding library inspired by Processing/p5.js/openFrameworks. It provides a `Sketch` protocol for declarative frame-based rendering, with 2D/3D drawing, GPU compute, post-processing, physics, audio, and more. macOS (Apple Silicon) only.

### Module Structure

Multi-target SPM architecture. `import metaphor` (umbrella, re-exports all via `@_exported import`) or import individual modules:

- **Tier 1 (no Core dependency)**: MetaphorAudio, MetaphorNetwork, MetaphorPhysics, MetaphorML
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

## Conventions

- macOS 14.0+ (Apple Silicon), Swift 5.10+
- Uses Swift Testing framework (`@Suite`, `@Test`), not XCTest
- New examples should follow existing directory structure: `Examples/{Category}/{Subcategory}/{Name}/`
- Each example is an independent SPM package with its own `Package.swift`
