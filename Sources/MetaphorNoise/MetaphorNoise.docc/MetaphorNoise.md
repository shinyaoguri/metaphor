# ``MetaphorNoise``

GameplayKit を使用したプロシージャルノイズ生成。

## Overview

MetaphorNoise は GameplayKit のノイズシステムをクリエイティブコーディング向けにラップします。
Perlin、Voronoi、billow、ridged などのノイズを float 値、2D グリッド、
または Metal テクスチャとして生成できます。フラクタル設定、
ノイズ合成（加算・乗算）、変換（タービュランス、クランプ、べき乗）をサポートします。

このモジュールは `MImage` および Metal テクスチャ処理のために MetaphorCore に依存します。
アンブレラモジュール（`import metaphor`）使用時は、`createNoise(type:config:)` などの
便利なメソッドからアクセスできます。

### クイックスタート

```swift
let noise = GKNoiseWrapper(
    type: .perlin,
    config: NoiseConfig(frequency: 4.0, octaves: 6),
    device: device
)

// 個別の点をサンプリング
let value = noise.sample(x: 0.5, y: 0.3)

// レンダリング用テクスチャを生成
let texture = noise.texture(width: 512, height: 512)
```

## Topics

### ノイズタイプ

- ``NoiseType``

### 設定

- ``NoiseConfig``

### ジェネレータ

- ``GKNoiseWrapper``
