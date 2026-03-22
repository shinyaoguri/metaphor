# ``MetaphorMPS``

Metal Performance Shaders によるハードウェアアクセラレーション画像処理とレイトレーシング。

## Overview

MetaphorMPS は Apple の Metal Performance Shaders フレームワークを通じて、
GPU 最適化された画像フィルタとレイトレーシングを提供します。
``MPSImageFilterWrapper`` はガウシアンブラー、Sobel エッジ検出、モルフォロジー演算などを提供し、
``MPSRayTracer`` はメッシュベースのレイトレーシングで、アンビエントオクルージョン、
ソフトシャドウ、ディフューズシェーディングモードに対応します。

``PostEffect`` 実装（``MPSBlurEffect``、``MPSSobelEffect`` 等）も含まれており、
ポストプロセスパイプラインで直接使用できます。

このモジュールは MetaphorCore に依存します。
アンブレラモジュール（`import metaphor`）使用時は、`createMPSFilter()` などの
便利なメソッドからアクセスできます。

### クイックスタート

```swift
let filter = MPSImageFilterWrapper(device: device, commandQueue: queue)

// 画像にガウシアンブラーを適用
filter.gaussianBlur(image, sigma: 5.0)

// ポストプロセスエフェクトとして使用
let blur = MPSBlurEffect(sigma: 3.0)
postProcess(blur)
```

## Topics

### 画像フィルタ

- ``MPSImageFilterWrapper``

### ポストプロセスエフェクト

- ``MPSBlurEffect``
- ``MPSSobelEffect``
- ``MPSErodeEffect``
- ``MPSDilateEffect``

### レイトレーシング

- ``MPSRayTracer``
- ``RayTraceMode``
