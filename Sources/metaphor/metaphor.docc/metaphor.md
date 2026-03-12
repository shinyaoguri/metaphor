# ``metaphor``

A Swift + Metal creative coding library inspired by Processing, p5.js, and openFrameworks.

## Overview

metaphor provides an immediate-mode creative coding environment powered by Metal.
Implement the `Sketch` protocol and start drawing — the library handles window creation,
render loop, and GPU pipeline setup automatically.

```swift
import metaphor

@main
final class MySketch: Sketch {
    func setup() {
        size(1280, 720)
    }

    func draw() {
        background(0.1)
        fill(Color.white)
        circle(width / 2, height / 2, 200)
    }
}
```

### Two-Pass Rendering

metaphor uses a two-pass rendering architecture:

1. **Offscreen Pass** — Your `draw()` code renders to an offscreen texture at the resolution you specify.
2. **Blit Pass** — A built-in pipeline composites the offscreen texture to the window with aspect-ratio preservation.

This decouples rendering resolution from window size and enables features like Syphon output
and video export at a fixed resolution.

### Three-Layer API

- **Sketch** — The top-level protocol you implement. Provides convenience methods via extensions.
- **SketchContext** — The bridge layer that manages drawing state, transforms, and rendering context.
- **Canvas2D / Canvas3D** — Low-level drawing backends that issue Metal draw calls.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Architecture>
- ``MetaphorCore/Sketch``
- ``MetaphorCore/SketchConfig``

### Core

- ``MetaphorCore/MetaphorRenderer``
- ``MetaphorCore/TextureManager``
- ``MetaphorCore/ShaderLibrary``
- ``MetaphorCore/PipelineFactory``
- ``MetaphorCore/MetaphorError``

### 2D Drawing

- ``MetaphorCore/Canvas2D``
- ``MetaphorCore/Graphics``
- ``MetaphorCore/MImage``
- ``MetaphorCore/DrawingStyle``
- ``MetaphorCore/ImageFilter``
- ``MetaphorCore/FilterType``
- ``MetaphorCore/TextAlignH``
- ``MetaphorCore/TextAlignV``

### 2D Drawing Modes

- ``MetaphorCore/RectMode``
- ``MetaphorCore/EllipseMode``
- ``MetaphorCore/ImageMode``
- ``MetaphorCore/ArcMode``
- ``MetaphorCore/ShapeMode``
- ``MetaphorCore/CloseMode``
- ``MetaphorCore/StrokeCap``
- ``MetaphorCore/StrokeJoin``
- ``MetaphorCore/GradientAxis``

### 3D Drawing

- ``MetaphorCore/Canvas3D``
- ``MetaphorCore/Graphics3D``
- ``MetaphorCore/CustomMaterial``
- ``MetaphorCore/ShadowMap``

### Geometry

- ``MetaphorCore/Mesh``
- ``MetaphorCore/DynamicMesh``

### Animation

- ``MetaphorCore/Tween``
- ``MetaphorCore/Interpolatable``
- ``MetaphorCore/TweenManager``

### Compute

- ``MetaphorCore/ComputeKernel``
- ``MetaphorCore/GPUBuffer``
- ``MetaphorCore/ImageFilterGPU``

### Post-Processing

- ``MetaphorCore/PostEffect``
- ``MetaphorCore/CustomPostEffect``
- ``MetaphorCore/PostProcessPipeline``

### Particle System

- ``MetaphorCore/ParticleSystem``
- ``MetaphorCore/Particle``
- ``MetaphorCore/ParticleForce``
- ``MetaphorCore/EmitterShape``

### Audio

- ``MetaphorAudio/AudioAnalyzer``
- ``MetaphorAudio/SoundFile``

### Network

- ``MetaphorNetwork/OSCReceiver``
- ``MetaphorNetwork/OSCValue``
- ``MetaphorNetwork/MIDIManager``
- ``MetaphorNetwork/MIDIMessage``
- ``MetaphorNetwork/MIDIMessageType``

### Machine Learning

- ``MetaphorML/MLTextureConverter``

### Metal Performance Shaders

- ``MetaphorMPS/MPSImageFilterWrapper``
- ``MetaphorMPS/MPSRayTracer``
- ``MetaphorMPS/RayTraceMode``

### Core Image

- ``MetaphorCoreImage/CIFilterPreset``
- ``MetaphorCoreImage/CIFilterWrapper``

### Noise Generation

- ``MetaphorNoise/NoiseType``
- ``MetaphorNoise/NoiseConfig``
- ``MetaphorNoise/GKNoiseWrapper``

### Physics

- ``MetaphorPhysics/Physics2D``
- ``MetaphorPhysics/PhysicsBody2D``
- ``MetaphorPhysics/PhysicsShape2D``
- ``MetaphorPhysics/PhysicsConstraint2D``
- ``MetaphorPhysics/SpatialHash2D``

### Scene Graph

- ``MetaphorSceneGraph/Node``
- ``MetaphorSceneGraph/SceneRenderer``

### Render Graph

- ``MetaphorRenderGraph/RenderGraph``
- ``MetaphorRenderGraph/RenderPassNode``
- ``MetaphorRenderGraph/SourcePass``
- ``MetaphorRenderGraph/EffectPass``
- ``MetaphorRenderGraph/MergePass``

### UI

- ``MetaphorCore/MetaphorView``
- ``MetaphorCore/ParameterGUI``
- ``MetaphorCore/OrbitCamera``
- ``MetaphorCore/PerformanceHUD``

### Input

- ``MetaphorCore/InputManager``
- ``MetaphorCore/CaptureDevice``
- ``MetaphorCore/CameraPosition``

### Export

- ``MetaphorCore/VideoExporter``
- ``MetaphorCore/VideoCodec``
- ``MetaphorCore/VideoFormat``
- ``MetaphorCore/VideoExportConfig``
- ``MetaphorCore/GIFExporter``
- ``MetaphorCore/FrameExporter``

### Syphon

- ``MetaphorCore/SyphonOutput``

### Color

- ``MetaphorCore/Color``
- ``MetaphorCore/ColorSpace``
- ``MetaphorCore/ColorModeConfig``

### Math & Vectors

- ``MetaphorCore/Vec2``
- ``MetaphorCore/Vec3``
- ``MetaphorCore/FrameTimer``

### Utilities

- ``MetaphorCore/NoiseGenerator``

### Errors

- ``MetaphorCore/MetaphorError``
- ``MetaphorAudio/SoundFileError``
- ``MetaphorNetwork/OSCReceiverError``
