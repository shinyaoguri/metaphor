# ``metaphor``

@Metadata {
    @DisplayName("metaphor")
    @PageColor(purple)
    @PageImage(
        purpose: icon,
        source: "metaphor-icon",
        alt: "metaphor ライブラリのアイコン"
    )
    @PageImage(
        purpose: card,
        source: "metaphor-card",
        alt: "metaphor ライブラリのカード画像"
    )
}

@Options {
    @TopicsVisualStyle(detailedGrid)
}

Processing、p5.js、openFrameworks にインスパイアされた Swift + Metal クリエイティブコーディングライブラリ。

## Overview

metaphor は Metal を活用したイミディエイトモードのクリエイティブコーディング環境を提供します。
`Sketch` プロトコルを実装するだけで、ウィンドウ生成、レンダーループ、GPU パイプラインの構築をライブラリが自動的に行います。

```swift
import metaphor

@main
final class MySketch: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 1280, height: 720)
    }

    func draw() {
        background(0.1)
        fill(Color.white)
        circle(width / 2, height / 2, 200)
    }
}
```

### 2パスレンダリング

metaphor は2パスレンダリングアーキテクチャを採用しています:

1. **オフスクリーンパス** — `draw()` のコードが、指定した解像度のオフスクリーンテクスチャにレンダリングされます。
2. **ブリットパス** — 内蔵パイプラインがオフスクリーンテクスチャをアスペクト比を維持したままウィンドウに合成します。

これによりレンダリング解像度がウィンドウサイズから分離され、Syphon 出力や動画エクスポートを固定解像度で行えます。

### 3レイヤー API

- **Sketch** — ユーザーが実装するトップレベルのプロトコル。エクステンションで便利なメソッドを提供します。
- **SketchContext** — 描画状態、トランスフォーム、レンダリングコンテキストを管理するブリッジレイヤー。
- **Canvas2D / Canvas3D** — Metal 描画コマンドを直接発行するローレベル描画バックエンド。

## Topics

### はじめに

- <doc:GettingStarted>
- <doc:Architecture>
- ``MetaphorCore/Sketch``
- ``MetaphorCore/SketchConfig``

### コア

- ``MetaphorCore/MetaphorRenderer``
- ``MetaphorCore/TextureManager``
- ``MetaphorCore/ShaderLibrary``
- ``MetaphorCore/PipelineFactory``
- ``MetaphorCore/MetaphorError``

### 2D 描画

- ``MetaphorCore/Canvas2D``
- ``MetaphorCore/Graphics``
- ``MetaphorCore/MImage``
- ``MetaphorCore/DrawingStyle``
- ``MetaphorCore/ImageFilter``
- ``MetaphorCore/FilterType``
- ``MetaphorCore/TextAlignH``
- ``MetaphorCore/TextAlignV``

### 2D 描画モード

- ``MetaphorCore/RectMode``
- ``MetaphorCore/EllipseMode``
- ``MetaphorCore/ImageMode``
- ``MetaphorCore/ArcMode``
- ``MetaphorCore/ShapeMode``
- ``MetaphorCore/CloseMode``
- ``MetaphorCore/StrokeCap``
- ``MetaphorCore/StrokeJoin``
- ``MetaphorCore/GradientAxis``

### 3D 描画

- ``MetaphorCore/Canvas3D``
- ``MetaphorCore/Graphics3D``
- ``MetaphorCore/CustomMaterial``
- ``MetaphorCore/ShadowMap``

### ジオメトリ

- ``MetaphorCore/Mesh``
- ``MetaphorCore/DynamicMesh``

### アニメーション

- ``MetaphorCore/Tween``
- ``MetaphorCore/Interpolatable``
- ``MetaphorCore/TweenManager``

### コンピュート

- ``MetaphorCore/ComputeKernel``
- ``MetaphorCore/GPUBuffer``
- ``MetaphorCore/ImageFilterGPU``

### ポストプロセス

- ``MetaphorCore/PostEffect``
- ``MetaphorCore/CustomPostEffect``
- ``MetaphorCore/PostProcessPipeline``

### パーティクルシステム

- ``MetaphorCore/ParticleSystem``
- ``MetaphorCore/Particle``
- ``MetaphorCore/ParticleForce``
- ``MetaphorCore/EmitterShape``

### オーディオ

- ``MetaphorAudio/AudioAnalyzer``
- ``MetaphorAudio/SoundFile``

### ネットワーク

- ``MetaphorNetwork/OSCReceiver``
- ``MetaphorNetwork/OSCValue``
- ``MetaphorNetwork/MIDIManager``
- ``MetaphorNetwork/MIDIMessage``
- ``MetaphorNetwork/MIDIMessageType``

### 機械学習

- ``MetaphorML/MLTextureConverter``

### Metal Performance Shaders

- ``MetaphorMPS/MPSImageFilterWrapper``
- ``MetaphorMPS/MPSRayTracer``
- ``MetaphorMPS/RayTraceMode``

### Core Image

- ``MetaphorCoreImage/CIFilterPreset``
- ``MetaphorCoreImage/CIFilterWrapper``

### ノイズ生成

- ``MetaphorNoise/NoiseType``
- ``MetaphorNoise/NoiseConfig``
- ``MetaphorNoise/GKNoiseWrapper``

### 物理演算

- ``MetaphorPhysics/Physics2D``
- ``MetaphorPhysics/PhysicsBody2D``
- ``MetaphorPhysics/PhysicsShape2D``
- ``MetaphorPhysics/PhysicsConstraint2D``
- ``MetaphorPhysics/SpatialHash2D``

### シーングラフ

- ``MetaphorSceneGraph/Node``
- ``MetaphorSceneGraph/SceneRenderer``

### レンダーグラフ

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

### 入力

- ``MetaphorCore/InputManager``
- ``MetaphorCore/CaptureDevice``
- ``MetaphorCore/CameraPosition``

### エクスポート

- ``MetaphorCore/VideoExporter``
- ``MetaphorCore/VideoCodec``
- ``MetaphorCore/VideoFormat``
- ``MetaphorCore/VideoExportConfig``
- ``MetaphorCore/GIFExporter``
- ``MetaphorCore/FrameExporter``

### Syphon

- ``MetaphorCore/SyphonOutput``

### カラー

- ``MetaphorCore/Color``
- ``MetaphorCore/ColorSpace``
- ``MetaphorCore/ColorModeConfig``

### 数学・ベクトル

- ``MetaphorCore/Vec2``
- ``MetaphorCore/Vec3``
- ``MetaphorCore/FrameTimer``

### ユーティリティ

- ``MetaphorCore/NoiseGenerator``

### エラー

- ``MetaphorCore/MetaphorError``
- ``MetaphorAudio/SoundFileError``
- ``MetaphorNetwork/OSCReceiverError``
