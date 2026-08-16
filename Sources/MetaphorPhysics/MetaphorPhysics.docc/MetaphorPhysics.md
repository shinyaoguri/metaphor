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
広域位相の衝突検出には ``SpatialHash2D`` を使用し、多数のボディを効率的に処理します。

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

// 描画ループ内:
physics.step(deltaTime)
circle(ball.position.x, ball.position.y, 40)
```

## Topics

### 物理ワールド

- ``Physics2D``

### ボディとシェイプ

- ``PhysicsBody2D``
- ``PhysicsShape2D``

### コンストレイント

- ``PhysicsConstraint2D``

### 衝突検出

- ``SpatialHash2D``
