import metaphor

/// シーングラフ + 即時描画のハイブリッドサンプル。
///
/// シーングラフ: 多関節アームの階層管理（各関節の回転が子に自動伝播）
/// 即時描画: アーム先端の軌跡を履歴として描画（ツリーに属さない動的データ）
///
/// → 構造的なものはシーングラフ、手続き的なものは即時描画、という使い分け。
@main
final class SceneGraphHybrid: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 800, height: 600, title: "Scene Graph Hybrid")
    }

    // --- シーングラフ側: 多関節アーム ---
    var root: Node!
    var joint1: Node!
    var joint2: Node!
    var joint3: Node!
    var tip: Node!

    // --- 即時描画側: 軌跡の履歴 ---
    let maxTrail = 600
    var trail: [(x: Float, y: Float)] = []

    func setup() {
        // アームのシーングラフを組み立てる
        // root → joint1 → joint2 → joint3 → tip
        root = createNode("root")

        joint1 = createNode("joint1")
        joint1.onDraw = { [self] in
            fill(80, 80, 80)
            noStroke()
            sphere(10)
        }
        root.addChild(joint1)

        joint2 = createNode("joint2")
        joint2.position = SIMD3(120, 0, 0)
        joint2.onDraw = { [self] in
            fill(100, 100, 100)
            noStroke()
            sphere(8)
        }
        joint1.addChild(joint2)

        joint3 = createNode("joint3")
        joint3.position = SIMD3(90, 0, 0)
        joint3.onDraw = { [self] in
            fill(120, 120, 120)
            noStroke()
            sphere(6)
        }
        joint2.addChild(joint3)

        tip = createNode("tip")
        tip.position = SIMD3(60, 0, 0)
        tip.onDraw = { [self] in
            fill(255, 120, 60)
            noStroke()
            sphere(5)
        }
        joint3.addChild(tip)
    }

    func draw() {
        background(15)

        let cx = Float(width) / 2
        let cy = Float(height) / 2
        let t = Float(frameCount) * 0.02

        // --- シーングラフ: アームのアニメーション ---
        // 各関節を異なる速度・振幅で回転させる（スピログラフ的な動き）
        joint1.setRotation(z: t * 1.0)
        joint2.setRotation(z: t * 2.7)
        joint3.setRotation(z: t * -4.1)

        // 先端のワールド座標を取得して軌跡に追加
        let world = tip.worldTransform
        let tipX = world.columns.3.x + cx
        let tipY = world.columns.3.y + cy
        trail.append((x: tipX, y: tipY))
        if trail.count > maxTrail {
            trail.removeFirst()
        }

        // --- 即時描画: 軌跡 ---
        // 古い点ほど暗く細く、新しい点ほど明るく太く
        noFill()
        for i in 1..<trail.count {
            let ratio = Float(i) / Float(trail.count)
            let alpha = ratio * 255
            stroke(255, 140, 60, alpha)
            strokeWeight(ratio * 3)
            line(trail[i - 1].x, trail[i - 1].y,
                 trail[i].x, trail[i].y)
        }

        // --- 即時描画: 関節間のボーン ---
        stroke(200)
        strokeWeight(2)
        let positions = [joint1, joint2, joint3, tip].map { node -> (Float, Float) in
            let w = node!.worldTransform
            return (w.columns.3.x + cx, w.columns.3.y + cy)
        }
        for i in 0..<positions.count - 1 {
            line(positions[i].0, positions[i].1,
                 positions[i + 1].0, positions[i + 1].1)
        }

        // --- シーングラフ: アーム本体を描画 ---
        push()
        translate(cx, cy, 0)
        drawScene(root)
        pop()
    }
}
