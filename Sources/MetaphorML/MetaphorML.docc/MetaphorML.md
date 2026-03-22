# ``MetaphorML``

@Metadata {
    @PageColor(blue)
}

@Options {
    @TopicsVisualStyle(compactGrid)
}

Core ML モデルと Metal レンダリングを統合するためのテクスチャ変換ユーティリティ。

## Overview

MetaphorML は Metal テクスチャと Core ML が使用するデータ形式のブリッジとなる
``MLTextureConverter`` を提供します。`MTLTexture`、`CVPixelBuffer`、`CGImage`、
`MLMultiArray` 間を自由に変換し、GPU レンダリング済みフレームを ML モデルに入力したり、
モデル出力をテクスチャとして描画したりできます。

このモジュールは MetaphorCore に依存せず、単独で使用できます。
`MetaphorML` を直接インポートするか、アンブレラモジュール（`import metaphor`）を使用してください。

### クイックスタート

```swift
let converter = MLTextureConverter(device: device, commandQueue: queue)

// レンダリング済みフレームを Core ML モデルに入力
let pixelBuffer = converter.pixelBuffer(from: renderTexture)

// モデル出力をテクスチャとして描画
let outputTexture = converter.texture(from: modelOutput)
```

## Topics

### テクスチャ変換

- ``MLTextureConverter``
