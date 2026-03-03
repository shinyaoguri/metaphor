# ``metaphor``

A Swift + Metal creative coding library inspired by Processing, p5.js, and openFrameworks.

## Overview

metaphor provides an immediate-mode creative coding environment powered by Metal.
Implement the ``Sketch`` protocol and start drawing — the library handles window creation,
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
- ``Sketch``
- ``SketchConfig``

### Core

- ``MetaphorRenderer``
- ``TextureManager``
- ``ShaderLibrary``
- ``PipelineFactory``
- ``MetaphorError``

### 2D Drawing

- ``Canvas2D``
- ``Graphics``
- ``MImage``
- ``DrawingStyle``
- ``ImageFilter``
- ``FilterType``
- ``TextAlignH``
- ``TextAlignV``

### 2D Drawing Modes

- ``RectMode``
- ``EllipseMode``
- ``ImageMode``
- ``ArcMode``
- ``ShapeMode``
- ``CloseMode``
- ``StrokeCap``
- ``StrokeJoin``
- ``GradientAxis``

### 3D Drawing

- ``Canvas3D``
- ``Graphics3D``
- ``CustomMaterial``
- ``ShadowMap``

### Geometry

- ``Mesh``
- ``DynamicMesh``

### Animation

- ``Tween``
- ``Interpolatable``
- ``TweenManager``

### Compute

- ``ComputeKernel``
- ``GPUBuffer``
- ``ImageFilterGPU``

### Post-Processing

- ``PostEffect``
- ``CustomPostEffect``
- ``PostProcessPipeline``

### Particle System

- ``ParticleSystem``
- ``Particle``
- ``ParticleForce``
- ``EmitterShape``

### Audio

- ``AudioAnalyzer``
- ``SoundFile``

### Network

- ``OSCReceiver``
- ``OSCValue``
- ``MIDIManager``
- ``MIDIMessage``
- ``MIDIMessageType``

### Machine Learning

- ``MLTextureConverter``

### Metal Performance Shaders

- ``MPSImageFilterWrapper``
- ``MPSRayTracer``
- ``RayTraceMode``

### Core Image

- ``CIFilterPreset``
- ``CIFilterWrapper``

### Noise Generation

- ``NoiseType``
- ``NoiseConfig``
- ``GKNoiseWrapper``

### Physics

- ``Physics2D``
- ``PhysicsBody2D``
- ``PhysicsShape2D``
- ``PhysicsConstraint2D``
- ``SpatialHash2D``

### Scene Graph

- ``Node``
- ``SceneRenderer``

### Render Graph

- ``RenderGraph``
- ``RenderPassNode``
- ``SourcePass``
- ``EffectPass``
- ``MergePass``

### UI

- ``MetaphorView``
- ``ParameterGUI``
- ``OrbitCamera``
- ``PerformanceHUD``

### Input

- ``InputManager``
- ``CaptureDevice``
- ``CameraPosition``

### Export

- ``VideoExporter``
- ``VideoCodec``
- ``VideoFormat``
- ``VideoExportConfig``
- ``GIFExporter``
- ``FrameExporter``

### Syphon

- ``SyphonOutput``

### Color

- ``Color``
- ``ColorSpace``
- ``ColorModeConfig``

### Math & Vectors

- ``Vec2``
- ``Vec3``
- ``FrameTimer``

### Utilities

- ``NoiseGenerator``

### Errors

- ``MetaphorError``
- ``Canvas2DError``
- ``MImageError``
- ``CustomMaterialError``
- ``ComputeKernelError``
- ``MeshError``
- ``ParticleError``
- ``SoundFileError``
- ``OSCReceiverError``
- ``GIFExporterError``
- ``MLError``
- ``MPSError``
