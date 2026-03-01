import metaphor

/// Feature 11: 3D オフスクリーン描画 + Feature 5: Model I/O 参照
///
/// 2つの独立した 3D シーンをオフスクリーンで描画し、
/// メイン 2D キャンバスに並べて合成するデモ。
/// Model I/O でモデルを読み込むこともできる（loadModel() を使用）。
@main
final class OffscreenMixExample: Sketch {
    var scene1: Graphics3D!
    var scene2: Graphics3D!

    var config: SketchConfig {
        SketchConfig(width: 1920, height: 1080, title: "Offscreen 3D Mix")
    }

    func setup() {
        scene1 = createGraphics3D(800, 800)
        scene2 = createGraphics3D(800, 800)
    }

    func draw() {
        background(Color(gray: 0.02))

        // --- シーン 1: 幾何学的な構成 ---
        scene1.beginDraw(time: time)
        drawScene1()
        scene1.endDraw()

        // --- シーン 2: 動くオブジェクト群 ---
        scene2.beginDraw(time: time)
        drawScene2()
        scene2.endDraw()

        // --- 2D キャンバスに合成 ---
        let padding: Float = 40
        let sceneW = (width - padding * 3) / 2
        let sceneH = sceneW  // 正方形
        let y = (height - sceneH) / 2

        // 枠 + 影
        noStroke()
        fill(Color(gray: 0.0, alpha: 0.3))
        rect(padding + 4, y + 4, sceneW, sceneH)
        rect(padding * 2 + sceneW + 4, y + 4, sceneW, sceneH)

        image(scene1, padding, y, sceneW, sceneH)
        image(scene2, padding * 2 + sceneW, y, sceneW, sceneH)

        // 枠線
        noFill()
        stroke(Color(gray: 0.3))
        strokeWeight(2)
        rect(padding, y, sceneW, sceneH)
        rect(padding * 2 + sceneW, y, sceneW, sceneH)
        noStroke()

        // ラベル
        fill(.white)
        textSize(16)
        textAlign(.center, .bottom)
        text("Scene A - Geometric", padding + sceneW / 2, y - 10)
        text("Scene B - Orbital", padding * 2 + sceneW + sceneW / 2, y - 10)

        textSize(12)
        fill(Color(gray: 0.5))
        textAlign(.center, .top)
        text("createGraphics3D() - Independent 3D render targets composited in 2D", width / 2, y + sceneH + 15)
    }

    // MARK: - Scene 1: 幾何学的構成

    private func drawScene1() {
        scene1.lights()
        scene1.ambientLight(0.4)
        scene1.directionalLight(0.5, -1, 0.3)

        // 中央のトーラス
        scene1.pushMatrix()
        scene1.rotateX(time * 0.5)
        scene1.rotateY(time * 0.7)
        scene1.fill(Color(hue: 0.55, saturation: 0.7, brightness: 1.0))
        scene1.specular(Color(gray: 0.6))
        scene1.shininess(64)
        scene1.torus(ringRadius: 150, tubeRadius: 40, detail: 32)
        scene1.popMatrix()

        // 周囲のボックス群
        for i in 0..<6 {
            let angle = Float(i) / 6.0 * Float.pi * 2 + time * 0.3
            scene1.pushMatrix()
            scene1.translate(cos(angle) * 250, 0, sin(angle) * 250)
            scene1.rotateY(time + Float(i))
            scene1.fill(Color(hue: Float(i) / 6.0, saturation: 0.8, brightness: 0.9))
            scene1.box(60)
            scene1.popMatrix()
        }
    }

    // MARK: - Scene 2: 軌道系

    private func drawScene2() {
        scene2.lights()
        scene2.ambientLight(0.3)
        scene2.pointLight(0, 0, 0, color: Color(r: 1, g: 0.9, b: 0.7))

        // 中心の光源球
        scene2.fill(Color(r: 1, g: 0.95, b: 0.6))
        scene2.emissive(Color(r: 0.8, g: 0.7, b: 0.3))
        scene2.sphere(50)
        scene2.emissive(0)

        // 軌道上の球体
        for ring in 0..<3 {
            let radius: Float = 120 + Float(ring) * 100
            let count = 4 + ring * 2
            let speed = 0.8 - Float(ring) * 0.2

            for i in 0..<count {
                let angle = Float(i) / Float(count) * Float.pi * 2 + time * speed
                let tilt = Float(ring) * 0.3
                let x = cos(angle) * radius
                let y = sin(tilt) * sin(angle) * radius * 0.3
                let z = sin(angle) * radius

                scene2.pushMatrix()
                scene2.translate(x, y, z)

                let hue = (Float(ring) * 0.3 + Float(i) * 0.1)
                    .truncatingRemainder(dividingBy: 1.0)
                scene2.fill(Color(hue: hue, saturation: 0.7, brightness: 1.0))
                scene2.specular(Color(gray: 0.5))

                let size: Float = 25 - Float(ring) * 5
                scene2.sphere(size, detail: 16)
                scene2.popMatrix()
            }
        }
    }
}
