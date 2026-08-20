# ``MetaphorPhysics``

@Metadata {
    @PageColor(orange)
}

@Options {
    @TopicsVisualStyle(compactGrid)
}

Verlet 積分と空間ハッシュによる 2D 物理シミュレーション。

## Overview

MetaphorPhysics は Verlet 積分を使用した軽量な 2D 物理エンジンを提供します。
円や矩形のシェイプを持つ剛体を作成し、距離コンストレイントで接続したり
ワールド座標にピン留めしたりして、毎フレームシミュレーションを更新します。
広域位相の衝突検出には ``MetaphorPhysics/SpatialHash2D`` を使用し、多数のボディを効率的に処理します。

このモジュールは MetaphorCore に依存せず、単独で使用できます。
アンブレラモジュール（`import metaphor`）使用時は、`createPhysics2D()` などの
便利なメソッドからアクセスできます。

### クイックスタート

```swift
let physics = Physics2D(cellSize: 50)
physics.setGravity(0, 500)
physics.bounds = (min: SIMD2(0, 0), max: SIMD2(800, 600))

// bounds の壁は「同じ係数を持つ動かないボディ」として振る舞う。置いた静的ボディと
// 挙動は同じで、跳ねずに溜めたいときはボディ側の restitution を 0 にする
let platform = physics.addRect(x: 400, y: 400, width: 300, height: 20)
platform.isStatic = true

let ball = physics.addCircle(x: 400, y: 100, radius: 20)
ball.restitution = 0.8

// 描画ループ内: 実フレーム時間は advance() へ渡す（step() ではない）
physics.advance(deltaTime)
circle(ball.position.x, ball.position.y, 40)
```

> Important: `step(_:iterations:)` には**固定刻み**を渡します。Verlet は速度を
> 「1 ステップあたりの変位」で持ち、反発の静定閾値も `dt²` に比例するため、
> 揺れる実フレーム時間をそのまま渡すとエネルギーが出入りし、同じスケッチが
> 実行のたび・機械ごとに違う動きになります。実フレーム時間から回すときは
> `advance(_:iterations:)` を使ってください — 経過時間を溜めて
> `fixedTimeStep`（既定 1/120 秒）で消化するので、フレーム時間の揺れに
> 結果が依存しなくなります（`import metaphor` の自動サブシステム更新も
> こちらを通ります）。`step()` は自分で刻みを決める場合（固定刻みループ、
> オフラインレンダリング、テスト）向けの低レベル API として残っています。
