# ``MetaphorCore``

The rendering engine, drawing system, and sketch protocol at the heart of metaphor.

## Overview

MetaphorCore provides the core Metal rendering pipeline, 2D/3D drawing backends,
compute shader support, and the ``Sketch`` protocol that ties everything together.

Most users should `import metaphor` (the umbrella module) rather than importing
MetaphorCore directly. See the
[full API reference](https://shinyaoguri.github.io/metaphor/documentation/metaphor)
for all modules including audio, physics, ML, and more.

## Topics

### Sketch Protocol

- ``Sketch``
- ``SketchConfig``

### Core Infrastructure

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

### Animation

- ``Tween``
- ``Interpolatable``
- ``TweenManager``

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
