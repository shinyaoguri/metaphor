---
title: 入門
part: 1
slug: getting-started
description: metaphor のスケッチを動かし、骨格と座標系、描画の止め方を覚えます。
draft: true
---

# 第 1 部 入門

> **この部はまだ執筆中です。** 本文は [#488](https://github.com/shinyaoguri/metaphor/issues/488)
> で書きます。いま置かれているのは、コード埋め込みの基盤（[#485](https://github.com/shinyaoguri/metaphor/issues/485)）
> が動いていることを示す骨組みです。章立てと執筆規約は [README.md](README.md) が正典です。

## 1.1 metaphor とは

（執筆予定: 何ができるライブラリか、動作環境、ドキュメントの地図）

## 1.2 インストールと最初のスケッチ

（執筆予定: CLI の導入、`metaphor new` / `metaphor run`、ウィンドウが出るまで）

## 1.3 スケッチの骨格

![スケッチの骨格の実行結果](images/01-GettingStarted/03-SketchSkeleton.png)

スケッチは `Sketch` プロトコルに準拠した 1 つの型です。役割は 3 つに分かれます。
`config` が起動時の設定、`setup()` が最初に一度だけ、`draw()` が毎フレーム呼ばれます。

<!-- tutorial-snippet: 01-GettingStarted/03-SketchSkeleton -->
```swift
import metaphor

@main
final class SketchSkeleton: Sketch {
    // config: 起動時に一度だけ読まれる設定。ウィンドウの大きさとタイトルを決める
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Sketch Skeleton")
    }

    // draw() をまたいで持ち越したい値は、プロパティとして持つ
    var angle: Float = 0

    // setup(): 起動時に一度だけ呼ばれる。描き始める前の準備をここに書く
    func setup() {
        noStroke()
        fill(255, 140, 40)
    }

    // draw(): 毎フレーム呼ばれる。1 回の呼び出しで 1 枚の絵を描く
    func draw() {
        background(24)
        push()
        translate(width * 0.5, height * 0.5)
        rotate(angle)
        rect(-60, -60, 120, 120)
        pop()
        angle += 0.01
    }
}
```

実行: `cd Examples/Tutorial/01-GettingStarted/03-SketchSkeleton && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- `angle += 0.01` の数を変えると、回転の速さはどうなりますか
- `background(24)` を `draw()` から消すと、何が残りますか

## 1.4 キャンバスと座標系

![キャンバスと座標系の実行結果](images/01-GettingStarted/04-CanvasAndCoordinates.png)

原点は左上で、`y` は下に向かって増えます。キャンバスの大きさは `width` と `height`
で取れるので、`config` の数値を直接書かずに済みます。

<!-- tutorial-snippet: 01-GettingStarted/04-CanvasAndCoordinates -->
```swift
import metaphor

@main
final class CanvasAndCoordinates: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Canvas and Coordinates")
    }

    func setup() {
        // 動かない絵なので、1 フレームだけ描いて止める
        noLoop()
    }

    func draw() {
        background(24)

        // 20 ピクセルごとの目盛り
        stroke(64)
        strokeWeight(1)
        var x: Float = 0
        while x <= width {
            line(x, 0, x, height)
            x += 20
        }
        var y: Float = 0
        while y <= height {
            line(0, y, width, y)
            y += 20
        }

        noStroke()

        // 原点 (0, 0) は左上。y は下向きに増える
        fill(255, 80, 80)
        circle(0, 0, 40)

        // 中心は (width / 2, height / 2)
        fill(80, 200, 255)
        circle(width * 0.5, height * 0.5, 40)

        // 右下の角が (width, height)
        fill(255, 220, 80)
        circle(width, height, 40)
    }
}
```

実行: `cd Examples/Tutorial/01-GettingStarted/04-CanvasAndCoordinates && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- `config` の `width` / `height` を変えても、3 つの円は角と中心に居続けますか
- 目盛りの間隔 `20` を変えると、格子はどう変わりますか

## 1.5 ライブ編集

（執筆予定: `metaphor watch` で保存のたびに再ビルドし、窓を保ったまま直す）

## 1.6 描画を止める・進める

![描画を止める・進めるの実行結果](images/01-GettingStarted/06-DrawControl.png)

`draw()` は既定で毎フレーム呼ばれ続けます。`noLoop()` で止め、`loop()` で再開し、
`redraw()` で 1 フレームだけ進められます。`frameRate(_:)` は 1 秒あたりの描画回数です。

<!-- tutorial-snippet: 01-GettingStarted/06-DrawControl -->
```swift
import metaphor

@main
final class DrawControl: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Draw Control")
    }

    var y: Float = 0
    var isRunning = true

    func setup() {
        // 1 秒あたりの描画回数。既定の 60 より遅くすると、線の動きが目で追える
        frameRate(30)
        y = height * 0.5
    }

    func draw() {
        background(24)
        stroke(255)
        strokeWeight(2)
        line(0, y, width, y)

        y -= 4
        if y < 0 { y = height }
    }

    // クリックで連続描画の停止 / 再開を切り替える
    func mousePressed() {
        isRunning.toggle()
        if isRunning {
            loop()
        } else {
            noLoop()
        }
    }

    // 止めている間は、キーを押すたびに 1 フレームだけ進む
    func keyPressed() {
        if !isRunning {
            redraw()
        }
    }
}
```

実行: `cd Examples/Tutorial/01-GettingStarted/06-DrawControl && swift run`
<!-- /tutorial-snippet -->

### 試してみる

- `frameRate(30)` を `frameRate(5)` にすると、線の動きはどう見えますか
- 止めた状態でキーを押し続けると、何が起きますか
