# ``MetaphorRenderGraph``

マルチパスレンダリングパイプラインのための合成可能なレンダーパスグラフ。

## Overview

MetaphorRenderGraph は複雑なマルチパスレンダリングパイプラインを構築するための
有向非巡回グラフ（DAG）を提供します。
オフスクリーンテクスチャにレンダリングするソースパスを作成し、
ポストプロセスエフェクトをチェーンし、複数のパスをブレンド操作でマージできます。

``SourcePass`` でオフスクリーンレンダーターゲットを描画コールバック付きで作成し、
``EffectPass`` でポストプロセスチェーンを適用し、``MergePass`` で
2つのパス出力をブレンドします。これらを ``RenderGraph`` に接続して自動実行します。

このモジュールは MetaphorCore に依存します。
`MetaphorRenderGraph` を直接インポートするか、アンブレラモジュール（`import metaphor`）を使用してください。

### クイックスタート

```swift
let passA = try SourcePass(label: "scene", device: device, width: 1280, height: 720)
passA.onDraw = { encoder, time in
    // シーン A を描画
}

let passB = try SourcePass(label: "overlay", device: device, width: 1280, height: 720)
passB.onDraw = { encoder, time in
    // シーン B を描画
}

let merged = try MergePass(passA, passB, blend: .add, device: device, shaderLibrary: shaders)
let graph = RenderGraph(root: merged)
```

## Topics

### グラフ

- ``RenderGraph``

### パスノード

- ``RenderPassNode``
- ``SourcePass``
- ``EffectPass``
- ``MergePass``
