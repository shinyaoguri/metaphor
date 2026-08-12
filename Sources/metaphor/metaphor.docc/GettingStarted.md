# metaphor をはじめよう

@Metadata {
    @PageColor(green)
    @CallToAction(
        purpose: link,
        url: "https://github.com/shinyaoguri/metaphor"
    )
}

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
    .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.9.0")
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
        background(25)

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

### 入力

マウスとキーボードの状態は毎フレーム読める値（`mouseX` / `mouseY` / `pmouseX` / `pmouseY` /
`isMousePressed` / `mouseButton` / `isKeyPressed` / `isKeyRepeat` / `key` / `keyCode`）として、
入力の発生は実装すれば呼ばれるコールバック（`mousePressed()` / `mouseReleased()` /
`mouseClicked()` / `mouseMoved()` / `mouseDragged()` / `mouseScrolled()` / `keyPressed()` /
`keyReleased()` / `keyTyped()`）として受け取ります。押しっぱなしのキーは
`isKeyDown(_:)` で 1 つずつ問い合わせます（同時押しに対応するため）。

個々のシグネチャは ``MetaphorCore/Sketch`` を参照してください。値とコールバックの使い分け、
当たり判定から UI を組み立てる方法は、チュートリアル
[第 4 部 入力を受ける](https://shinyaoguri.github.io/metaphor/tutorial/input/)で解説しています。

## 描画

```swift
@main
final class MySketch: Sketch {
    func draw() {
        background(0)
        fill(255, 0, 0)
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
- ``MetaphorSyphon/SyphonOutput`` で Syphon 出力を設定する
