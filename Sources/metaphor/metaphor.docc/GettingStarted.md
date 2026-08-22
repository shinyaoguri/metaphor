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
``/MetaphorCore/Sketch`` プロトコルを実装するだけで、ウィンドウ生成、Metal のセットアップ、レンダーループをライブラリが処理します。

このページは API リファレンス側の最小の導入で、インストールから最初のスケッチが動くところまでを扱います。
**metaphor がはじめてなら、[チュートリアル](https://shinyaoguri.github.io/metaphor/tutorial/)を順に読むのが近道です** —
各節に動くスケッチと実行結果の画像が付いていて、座標系・色・変換・動き・入力までを通しで学べます。

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
    .package(url: "https://github.com/shinyaoguri/metaphor.git", from: "0.12.0")
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

新しい Swift ファイルを作成し、``/MetaphorCore/Sketch`` プロトコルを実装します:

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

``/MetaphorCore/Sketch`` プロトコルは、特定のタイミングで呼ばれるコールバックメソッドを提供します:

- `setup()` — スケッチ開始時に一度だけ呼ばれます。リソースの読み込みや状態の初期化に使います。
- `draw()` — 毎フレーム呼ばれます。描画コードをここに書きます。
- `compute()` — 毎フレーム、描画の前に呼ばれます。GPU コンピュートディスパッチに使います。

連続描画を止める `noLoop()`、再開する `loop()`、1 フレームだけ描き直す `redraw()`、
フレームレートを指定する `frameRate(_:)` の使い分けは、チュートリアル
[第 1 部 入門](https://shinyaoguri.github.io/metaphor/tutorial/getting-started/)で解説しています。

## 設定

ウィンドウサイズ・タイトル・フレームレート・プラグイン（Syphon 出力など）は ``MetaphorCore/SketchConfig`` で指定し、
``/MetaphorCore/Sketch`` の `config` プロパティから返します。すべてのパラメータに既定値があるため、
`SketchConfig()` だけで 1920×1080・60fps のキャンバスが得られます。個々のパラメータは
``MetaphorCore/SketchConfig`` を参照してください。

`setup()` 内で `createCanvas(width:height:)` を呼べば、キャンバスサイズを動的に変更できます。
レンダリング解像度とウィンドウの大きさが別物である（`windowScale` で分離される）ことと、
そのために座標がどう振る舞うかは、チュートリアル
[第 1 部 入門](https://shinyaoguri.github.io/metaphor/tutorial/getting-started/)で扱っています。

### 組み込みプロパティ

キャンバスの大きさ（`width` / `height`）、描いたフレーム数（`frameCount`）、
経過時間（`time` / `deltaTime`）は、すべての ``/MetaphorCore/Sketch`` 実装からプロパティとして読めます。
型と意味は ``/MetaphorCore/Sketch`` を参照してください。

### 入力

マウスとキーボードの状態は毎フレーム読める値（`mouseX` / `mouseY` / `pmouseX` / `pmouseY` /
`isMousePressed` / `mouseButton` / `isKeyPressed` / `isKeyRepeat` / `key` / `keyCode`）として、
入力の発生は実装すれば呼ばれるコールバック（`mousePressed()` / `mouseReleased()` /
`mouseClicked()` / `mouseMoved()` / `mouseDragged()` / `mouseScrolled()` / `keyPressed()` /
`keyReleased()` / `keyTyped()`）として受け取ります。押しっぱなしのキーは
`isKeyDown(_:)` で 1 つずつ問い合わせます（同時押しに対応するため）。

個々のシグネチャは ``/MetaphorCore/Sketch`` を参照してください。値とコールバックの使い分け、
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

`background()`、`fill()`、`rect()`、`circle()` などの描画メソッドは ``/MetaphorCore/Sketch`` プロトコルの
エクステンションとして提供されます。内部では ``MetaphorCore/SketchContext`` に委譲されており、
`context` プロパティから直接アクセスすることもできます。

図形・色・線・自作の形・変換（`push` / `pop`）・テキスト・画像といった 2D の語彙は、チュートリアル
[第 2 部 2D を描く](https://shinyaoguri.github.io/metaphor/tutorial/drawing-2d/)がひととおり扱います。

## 次のステップ

- チュートリアル[第 1 部 入門](https://shinyaoguri.github.io/metaphor/tutorial/getting-started/)から順に読む
- ``MetaphorCore/Canvas2D`` で 2D 描画を探索する
- チュートリアル[第 5 部 3D へ](https://shinyaoguri.github.io/metaphor/tutorial/3d/)で 3D の描き方を通しで学ぶ（低レベル API は ``MetaphorCore/Canvas3D``）
- ``MetaphorCore/PostEffect`` でポストプロセスエフェクトを追加する
- Syphon 出力は別パッケージ [metaphor-syphon](https://github.com/shinyaoguri/metaphor-syphon) を依存に足して `plugins: [.syphon(name:)]` を渡す
