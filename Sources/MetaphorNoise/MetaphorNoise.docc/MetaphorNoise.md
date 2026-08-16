# ``MetaphorNoise``

@Metadata {
    @PageColor(teal)
}

@Options {
    @TopicsVisualStyle(compactGrid)
}

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

### 点で読むかグリッドで読むか（座標系が違う）

場を読む入口は 2 つあり、**それぞれ別の座標系で読みます**。

| 入口 | `origin` / `sampleScale` |
|---|---|
| `sample(x:y:)` | **効かない**（ノイズ空間をそのまま読む） |
| `sampleGrid` / `texture` / `image` / `colorMappedTexture` | 効く（`origin` を起点に `GKNoiseMap` へ委ねる） |

両者が一致するのはグリッドの最初の 1 点（`sample(x: origin.x, y: origin.y)`）だけです。
それ以降は一致せず、`origin + index × sampleScale` で追いかけても揃いません
（GameplayKit が `GKNoiseMap` を刻む間隔は `sampleScale` だけでは決まらず、
格子の `width` / `height` によっても変わります）。

**1 つのスケッチでは入口を片方に統一してください。** 混ぜると「絵と数値が食い違う」形で現れます。

## Topics

### ノイズタイプ

- ``NoiseType``

### 設定

- ``NoiseConfig``

### ジェネレータ

- ``GKNoiseWrapper``
