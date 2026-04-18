# ``MetaphorVideo``

@Metadata {
    @PageColor(purple)
}

@Options {
    @TopicsVisualStyle(compactGrid)
}

クリエイティブコーディングのためのビデオファイル再生。

## Overview

MetaphorVideo はビデオファイルの再生とフレーム単位のテクスチャ取得を提供します。
``VideoPlayer`` で MP4、MOV、M4V ファイルを再生し、
CVMetalTextureCache によるゼロコピーの Metal テクスチャとしてフレームを取得できます。

このモジュールは MetaphorCore に依存せず、単独で使用できます。
アンブレラモジュール（`import metaphor`）使用時は、`loadVideo()` や
`image(video, x, y)` などの便利なメソッドからアクセスできます。

### クイックスタート

```swift
let video = try loadVideo("/path/to/video.mp4")
video.loop()

// 描画ループ内:
video.update()
image(video, 0, 0, width, height)
```

## Topics

### ビデオ再生

- ``VideoPlayer``

### エラー

- ``VideoPlayerError``
