import metaphor

/// Scene graph の基本的な使い方を示すサンプル。
///
/// - 親子階層によるトランスフォーム伝播
/// - ノードごとのアニメーション
/// - lookAt によるノードの向き制御
@main
final class SceneGraphBasics: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 800, height: 600, title: "Scene Graph Basics")
    }

    // シーングラフのルートノード
    var root: Node!

    // 太陽系モデル: 太陽 → 地球 → 月
    var sun: Node!
    var earth: Node!
    var moon: Node!

    // 観察者ノード（lookAt デモ）
    var observer: Node!

    func setup() {
        // ルートノード
        root = createNode("root")

        // 太陽（中心に配置）
        sun = createNode("sun")
        sun.onDraw = { [self] in
            fill(255, 200, 50)
            noStroke()
            sphere(60)
        }
        root.addChild(sun)

        // 地球（太陽の子ノード — 太陽の回転に追従する）
        earth = createNode("earth")
        earth.position = SIMD3(200, 0, 0)
        earth.onDraw = { [self] in
            fill(50, 130, 255)
            noStroke()
            sphere(25)
        }
        sun.addChild(earth)

        // 月（地球の子ノード — 地球の公転 + 自転に追従する）
        moon = createNode("moon")
        moon.position = SIMD3(50, 0, 0)
        moon.onDraw = { [self] in
            fill(200, 200, 200)
            noStroke()
            sphere(8)
        }
        earth.addChild(moon)

        // 観察者（常に地球を向く小さなコーン）
        observer = createNode("observer")
        observer.position = SIMD3(-250, 120, 100)
        observer.onDraw = { [self] in
            fill(255, 80, 80)
            noStroke()
            cone(radius: 15, height: 30)
        }
        root.addChild(observer)
    }

    func draw() {
        background(20)
        lights()

        // カメラを少し引いて全体を見渡す
        translate(Float(width) / 2, Float(height) / 2, 0)

        let t = Float(frameCount) * 0.01

        // 太陽: ゆっくり自転
        sun.setRotation(y: t * 0.3)

        // 地球: 自転（太陽の子なので公転は太陽の回転で自動的に起きる）
        earth.setRotation(y: t * 2.0)

        // 月: 地球の周りを公転するように自前でも回転
        moon.setRotation(y: t * 3.0)

        // 観察者は常に地球のワールド位置を向く
        let earthWorldPos = SIMD3<Float>(
            earth.worldTransform.columns.3.x,
            earth.worldTransform.columns.3.y,
            earth.worldTransform.columns.3.z
        )
        observer.lookAt(earthWorldPos)

        // シーングラフを一括描画
        drawScene(root)
    }
}
