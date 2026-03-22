# metaphor をはじめよう

metaphor で最初のクリエイティブコーディングプロジェクトをセットアップします。

## Overview

metaphor は Swift + Metal のクリエイティブコーディングライブラリです。
``MetaphorCore/Sketch`` プロトコルを実装するだけで、ウィンドウ生成、Metal のセットアップ、レンダーループをライブラリが処理します。

## 動作環境

| 要件 | バージョン |
|-----|----------|
| macOS | 14.0+ |
| Swift | 5.10+ |
| Xcode | 15.0+ |

## インストール

`Package.swift` に metaphor を追加してください:

```swift
dependencies: [
    .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.2.1")
]
```

次にターゲットの dependencies に追加します:

```swift
.executableTarget(
    name: "MySketch",
    dependencies: [
        .product(name: "metaphor", package: "metaphor")
    ]
)
```

## 最初のスケッチを作る

新しい Swift ファイルを作成し、``MetaphorCore/Sketch`` プロトコルを実装します:

```swift
import metaphor

@main
final class MySketch: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 1280, height: 720)
    }

    func setup() {

    }

    func draw() {
        background(0.1)

        // 中央に白い円を描く
        fill(Color.white)
        noStroke()
        circle(width / 2, height / 2, 200)
    }
}
```

スケッチクラスに `@main` を付けて、アプリケーションのエントリポイントにしてください。

## スケッチのライフサイクル

``MetaphorCore/Sketch`` プロトコルは、特定のタイミングで呼ばれるコールバックメソッドを提供します:

- `setup()` — スケッチ開始時に一度だけ呼ばれます。リソースの読み込みや状態の初期化に使います。
- `draw()` — 毎フレーム呼ばれます。描画コードをここに書きます。
- `compute()` — 毎フレーム、描画の前に呼ばれます。GPU コンピュートディスパッチに使います。

## 設定

``MetaphorCore/SketchConfig`` でスケッチの動作をカスタマイズできます。
``MetaphorCore/Sketch`` クラスの `config` プロパティをオーバーライドしてください:

```swift
var config: SketchConfig {
    SketchConfig(
        width: 1920,       // オフスクリーンテクスチャの幅（デフォルト: 1920）
        height: 1080,      // オフスクリーンテクスチャの高さ（デフォルト: 1080）
        title: "My Sketch", // ウィンドウタイトル（デフォルト: "metaphor"）
        fps: 60,           // 目標フレームレート（デフォルト: 60）
        syphonName: nil,   // Syphon サーバー名、nil で無効（デフォルト: nil）
        windowScale: 0.5,  // ウィンドウサイズ = テクスチャサイズ × scale（デフォルト: 0.5）
        fullScreen: false,  // フルスクリーンで起動（デフォルト: false）
        renderLoopMode: .displayLink // .displayLink または .timer(fps:)（デフォルト: .displayLink）
    )
}
```

すべてのパラメータにデフォルト値があるため、`SketchConfig()` だけで 1920×1080、60fps のキャンバスが得られます。

`setup()` 内で `createCanvas(width:height:)` を使って動的にキャンバスサイズを変更することもできます:

```swift
func setup() {
    createCanvas(width: 800, height: 600)
}
```

### 組み込みプロパティ

すべての ``MetaphorCore/Sketch`` 実装で以下のプロパティにアクセスできます:

| プロパティ | 型 | 説明 |
|----------|------|------|
| `width` | `Float` | キャンバスの幅（ピクセル） |
| `height` | `Float` | キャンバスの高さ（ピクセル） |
| `frameCount` | `Int` | これまでにレンダリングされたフレーム数 |
| `time` | `Float` | スケッチ開始からの経過秒数 |
| `deltaTime` | `Float` | 前フレームからの経過秒数 |
| `mouseX` | `Float` | 現在のマウス X 座標 |
| `mouseY` | `Float` | 現在のマウス Y 座標 |
| `pmouseX` | `Float` | 前フレームのマウス X 座標 |
| `pmouseY` | `Float` | 前フレームのマウス Y 座標 |
| `isMousePressed` | `Bool` | マウスボタンが押されているか |
| `mouseButton` | `Int` | 現在押されているマウスボタン（0=左, 1=右, 2=中） |
| `isKeyPressed` | `Bool` | キーが押されているか |
| `key` | `Character?` | 最後に押されたキー |
| `keyCode` | `UInt16?` | 最後に押されたキーのキーコード |

### 入力イベントコールバック

以下のメソッドをオーバーライドしてユーザー入力に応答できます:

| メソッド | 説明 |
|--------|------|
| `mousePressed()` | マウスボタンが押された |
| `mouseReleased()` | マウスボタンが離された |
| `mouseMoved()` | マウスが移動した |
| `mouseDragged()` | マウスがドラッグされた |
| `mouseScrolled()` | マウススクロールイベント |
| `mouseClicked()` | マウスクリック（ドラッグなしの押下＋解放） |
| `keyPressed()` | キーが押された |
| `keyReleased()` | キーが離された |

## 描画

```swift
@main
final class MySketch: Sketch {
    func draw() {
        background(0)
        fill(1, 0, 0)
        rect(100, 100, 200, 150)
    }
}
```

`background()`、`fill()`、`rect()`、`circle()` などの描画メソッドは ``MetaphorCore/Sketch`` プロトコルの
エクステンションとして提供されます。内部では ``MetaphorCore/SketchContext`` に委譲されており、
`context` プロパティから直接アクセスすることもできます。

## 次のステップ

- ``MetaphorCore/Canvas2D`` で 2D 描画を探索する
- ``MetaphorCore/Canvas3D`` で 3D レンダリングを学ぶ
- ``MetaphorCore/PostEffect`` でポストプロセスエフェクトを追加する
- ``MetaphorCore/SyphonOutput`` で Syphon 出力を設定する
