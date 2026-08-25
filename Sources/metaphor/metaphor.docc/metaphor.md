# ``metaphor``

@Metadata {
    @DisplayName("metaphor")
    @PageColor(purple)
    @PageImage(
        purpose: icon,
        source: "metaphor-icon",
        alt: "The metaphor library icon"
    )
    @PageImage(
        purpose: card,
        source: "metaphor-card",
        alt: "The metaphor library card image"
    )
}

@Options {
    @TopicsVisualStyle(detailedGrid)
}

A Swift and Metal creative coding library inspired by Processing, p5.js, and openFrameworks.

## Overview

> Tip: This is **reference material to look things up in**. If this is your first time,
> the [tutorial](https://shinyaoguri.github.io/metaphor/tutorial/) reads front to back
> and is the faster way in (start with Part 1, "Getting Started").
> For the bigger picture, see [the metaphor site](https://shinyaoguri.github.io/metaphor/).

metaphor provides an immediate-mode creative coding environment built on Metal.
Implement the `Sketch` protocol and the library takes care of creating the window, running the render loop, and building the GPU pipeline.

```swift
import metaphor

@main
final class MySketch: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 1280, height: 720)
    }

    func draw() {
        background(25)
        fill(Color.white)
        circle(width / 2, height / 2, 200)
    }
}
```

### Installation

metaphor requires macOS 14.0+ (Apple Silicon), Swift 5.10+, and Xcode 15.0+.
Add one line to `dependencies` in your `Package.swift` and add
`.product(name: "metaphor", package: "metaphor")` to your target's `dependencies`, and the code above runs.

```swift
dependencies: [
    .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.14.0")
]
```

To follow installation through to your first running sketch step by step, the tutorial's
[Part 1, Getting Started](https://shinyaoguri.github.io/metaphor/tutorial/getting-started/) is the faster route
(it also covers getting started with the `metaphor` CLI).

### Two-Pass Rendering

metaphor uses a two-pass rendering architecture:

1. **Offscreen pass** — the code in `draw()` renders into an offscreen texture at the resolution you specify.
2. **Blit pass** — a built-in pipeline composites that offscreen texture into the window, preserving aspect ratio.

Separating render resolution from window size makes four things possible:

- **Resolution independence** — drawing always happens at the resolution you specified, whatever the window size (``MetaphorCore/TextureManager``).
- **External output** — send fixed-resolution frames to a live viewer or VJ software. Before the blit, registered output plugins (``MetaphorCore/MetaphorOutputPlugin``) receive the same offscreen texture (Syphon lives in the separate [metaphor-syphon](https://github.com/shinyaoguri/metaphor-syphon) package).
- **Video export** — write out frames at a consistent quality while keeping the window small.
- **Post-processing** — apply GPU effects to the offscreen texture before it is displayed (``MetaphorCore/PostEffect``).

### Three-Layer API

- **Sketch** — the top-level protocol you implement. Its extensions supply the convenience methods.
- **SketchContext** — the bridge layer that manages drawing state, transforms, and the rendering context.
- **Canvas2D / Canvas3D** — the low-level drawing backends that issue Metal draw commands directly.

### Bridge API

These are the methods that only appear with `import metaphor`. They are the glue that lets you call
optional subsystems — audio, video, physics, networking — from a `Sketch` in a single line,
and the umbrella target `metaphor` supplies them as extensions on `Sketch`.

```swift
import metaphor

@main
final class MySketch: Sketch {
    var audio: AudioAnalyzer?

    func setup() {
        let input = createAudioInput(fftSize: 2048)  // <- Bridge API
        try? input.start()
        audio = input
    }

    func draw() {
        guard let audio else { return }
        audio.update()
        background(18)
        circle(width / 2, height / 2, 100 + audio.volume * 600)
    }
}
```

A minimal setup that imports only `MetaphorCore` does not include these methods
(you would assemble `AudioAnalyzer` and the rest yourself).
For the full list, see the "Bridge API (...)" groups in Topics below.

## Topics

### Essentials

- ``/MetaphorCore/Sketch``
- ``MetaphorCore/SketchConfig``

### Bridge API (Audio)

- ``MetaphorCore/Sketch/createAudioInput(fftSize:)``
- ``MetaphorCore/Sketch/loadSound(_:)``

### Bridge API (Video)

- ``MetaphorCore/Sketch/loadVideo(_:)``
- ``MetaphorCore/Sketch/image(_:_:_:)``
- ``MetaphorCore/Sketch/image(_:_:_:_:_:)``

### Bridge API (Networking)

- ``MetaphorCore/Sketch/createOSCReceiver(port:)``
- ``MetaphorCore/Sketch/createOSCSender(host:port:)``
- ``MetaphorCore/Sketch/createMIDI()``

### Bridge API (Physics)

- ``MetaphorCore/Sketch/createPhysics2D(cellSize:)``

### Bridge API (Noise)

- ``MetaphorCore/Sketch/createNoise(_:config:)``
- ``MetaphorCore/Sketch/noiseTexture(_:width:height:config:)``

### Bridge API (Scene Graph)

- ``MetaphorCore/Sketch/createNode(_:)``
- ``MetaphorCore/Sketch/drawScene(_:)``

### Bridge API (Render Graph)

- ``MetaphorCore/Sketch/createSourcePass(label:width:height:)``
- ``MetaphorCore/Sketch/createEffectPass(_:effects:)``
- ``MetaphorCore/Sketch/createMergePass(_:_:blend:)``
- ``MetaphorCore/Sketch/setRenderGraph(_:)``

### Bridge API (Core Image)

- ``MetaphorCore/Sketch/ciFilter(_:_:)``
- ``MetaphorCore/Sketch/ciFilter(_:name:parameters:)``
- ``MetaphorCore/Sketch/ciGenerate(_:width:height:)``

### Bridge API (Metal Performance Shaders)

- ``MetaphorCore/Sketch/createMPSFilter()``
- ``MetaphorCore/Sketch/createRayTracer(width:height:)``

### Bridge API (Machine Learning)

- ``MetaphorCore/Sketch/createMLTextureConverter()``

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

### Particle Systems

- ``MetaphorCore/ParticleSystem``
- ``MetaphorCore/Particle``
- ``MetaphorCore/ParticleForce``
- ``MetaphorCore/EmitterShape``

### Audio

- ``MetaphorAudio/AudioAnalyzer``
- ``MetaphorAudio/SoundFile``

### Video

- ``MetaphorVideo/VideoPlayer``

### Networking

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
- ``MetaphorMPS/MPSBlurEffect``
- ``MetaphorMPS/MPSSobelEffect``
- ``MetaphorMPS/MPSErodeEffect``
- ``MetaphorMPS/MPSDilateEffect``

### Core Image

- ``MetaphorCoreImage/CIFilterPreset``
- ``MetaphorCoreImage/CIFilterWrapper``
- ``MetaphorCoreImage/CIFilterValue``
- ``MetaphorCoreImage/CIFilterEffect``
- ``MetaphorCoreImage/CIFilterRawEffect``

### Noise

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
- ``MetaphorSceneGraph/AABB``
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

### Output (Extension Points)

- ``MetaphorCore/MetaphorOutputPlugin``
- ``MetaphorCore/MetaphorOutputProvider``
- ``MetaphorCore/MetaphorOutputProviders``
- ``MetaphorCore/MetaphorOutputContext``
- ``MetaphorCore/PluginRequirements``
- ``MetaphorCore/ViewerOutputPlugin``

### Color

- ``MetaphorCore/Color``
- ``MetaphorCore/ColorSpace``
- ``MetaphorCore/ColorModeConfig``

### Math and Vectors

- ``MetaphorCore/Vec2``
- ``MetaphorCore/Vec3``
- ``MetaphorCore/FrameTimer``

### Utilities

- ``MetaphorCore/NoiseGenerator``

### Errors

- ``MetaphorCore/MetaphorError``
- ``MetaphorAudio/SoundFileError``
- ``MetaphorNetwork/OSCReceiverError``
- ``MetaphorVideo/VideoPlayerError``
