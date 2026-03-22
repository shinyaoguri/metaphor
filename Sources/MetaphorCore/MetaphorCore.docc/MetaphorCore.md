# ``MetaphorCore``

metaphor の中核となるレンダリングエンジン、描画システム、Sketch プロトコル。

## Overview

MetaphorCore は Metal レンダリングパイプライン、2D/3D 描画バックエンド、
コンピュートシェーダーサポート、そしてすべてを統合する ``Sketch`` プロトコルを提供します。

通常は MetaphorCore を直接インポートせず、`import metaphor`（アンブレラモジュール）を使用してください。
すべてのモジュール（オーディオ、物理演算、ML など）を含む
[完全な API リファレンスはこちら](https://shinyaoguri.github.io/metaphor/documentation/metaphor)。

## Topics

### Sketch プロトコル

- ``Sketch``
- ``SketchConfig``

### コアインフラ

- ``MetaphorRenderer``
- ``TextureManager``
- ``ShaderLibrary``
- ``PipelineFactory``
- ``MetaphorError``

### 2D 描画

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

### 3D 描画

- ``Canvas3D``
- ``Graphics3D``
- ``CustomMaterial``
- ``ShadowMap``

### ジオメトリ

- ``Mesh``
- ``DynamicMesh``

### コンピュート

- ``ComputeKernel``
- ``GPUBuffer``
- ``ImageFilterGPU``

### ポストプロセス

- ``PostEffect``
- ``CustomPostEffect``
- ``PostProcessPipeline``

### パーティクルシステム

- ``ParticleSystem``
- ``Particle``
- ``ParticleForce``
- ``EmitterShape``

### アニメーション

- ``Tween``
- ``Interpolatable``
- ``TweenManager``

### UI

- ``MetaphorView``
- ``ParameterGUI``
- ``OrbitCamera``
- ``PerformanceHUD``

### 入力

- ``InputManager``
- ``CaptureDevice``
- ``CameraPosition``

### エクスポート

- ``VideoExporter``
- ``VideoCodec``
- ``VideoFormat``
- ``VideoExportConfig``
- ``GIFExporter``
- ``FrameExporter``

### Syphon

- ``SyphonOutput``

### カラー

- ``Color``
- ``ColorSpace``
- ``ColorModeConfig``

### 数学・ベクトル

- ``Vec2``
- ``Vec3``
- ``FrameTimer``

### ユーティリティ

- ``NoiseGenerator``

### エラー

- ``MetaphorError``
