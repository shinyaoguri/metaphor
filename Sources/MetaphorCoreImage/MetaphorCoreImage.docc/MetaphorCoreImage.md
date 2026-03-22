# ``MetaphorCoreImage``

@Metadata {
    @PageColor(red)
}

@Options {
    @TopicsVisualStyle(compactGrid)
}

Metal ベースのクリエイティブコーディングのための Core Image フィルタ統合。

## Overview

MetaphorCoreImage は Apple の Core Image フレームワークと Metal テクスチャを橋渡しします。
``CIFilterPreset`` で厳選されたフィルタプリセット（ディストーション、スタイライズ、ブラー、
カラーエフェクト、ジェネレータなど）を適用するか、``CIFilterWrapper`` で任意の
Core Image フィルタを名前で使用できます。

``PostEffect`` 実装（``CIFilterEffect``、``CIFilterRawEffect``）も含まれており、
ポストプロセスパイプラインで直接使用できます。

このモジュールは MetaphorCore に依存します。
`MetaphorCoreImage` を直接インポートするか、アンブレラモジュール（`import metaphor`）を使用してください。

### クイックスタート

```swift
let ci = CIFilterWrapper(device: device, commandQueue: queue)

// プリセットフィルタを画像に適用
ci.apply(filterName: CIFilterPreset.twirl.filterName,
         parameters: CIFilterPreset.twirl.parameters(textureSize: size),
         to: image)

// ポストプロセスエフェクトとして使用
let effect = CIFilterEffect(.kaleidoscope)
postProcess(effect)
```

## Topics

### フィルタプリセット

- ``CIFilterPreset``

### フィルタラッパー

- ``CIFilterWrapper``
- ``CIFilterValue``

### ポストプロセスエフェクト

- ``CIFilterEffect``
- ``CIFilterRawEffect``
