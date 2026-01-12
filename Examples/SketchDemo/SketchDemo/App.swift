import SwiftUI
import metaphor

// MARK: - Sketch Protocol Demo

/// Sketchプロトコルを使ったクラスベースのスケッチ
/// Processing/p5.jsのような書き方ができる
class PolygonSketch: Sketch {
    var size: (width: Int, height: Int) { (800, 600) }

    // スケッチの状態
    var points: [SIMD2<Float>] = []
    var hue: Float = 0

    func setup() {
        // 初期化処理（1回だけ呼ばれる）
    }

    func draw(_ g: Graphics) {
        g.background(30)

        // HSBからRGBへ変換した色（簡易）
        let r = abs(sin(hue)) * 255
        let gr = abs(sin(hue + 2.094)) * 255
        let b = abs(sin(hue + 4.189)) * 255

        // 保存されたポイントで多角形を描画
        if points.count >= 3 {
            g.fill(r, gr, b, 150)
            g.stroke(255)
            g.strokeWeight(2)

            g.beginShape()
            for point in points {
                g.vertex(point.x, point.y)
            }
            g.endShape(.close)
        }

        // ポイントを個別に表示
        g.noStroke()
        g.fill(255)
        for point in points {
            g.ellipse(point.x, point.y, 10, 10)
        }

        // 現在のマウス位置にガイド表示
        g.stroke(255, 100)
        g.strokeWeight(1)
        if let last = points.last {
            g.line(last.x, last.y, g.mouseX, g.mouseY)
        }

        // 星形を回転させながら描画
        g.pushMatrix()
        g.translate(g.width - 100, 100)
        g.rotate(Float(g.frameCount) * 0.02)
        drawStar(g, cx: 0, cy: 0, radius1: 30, radius2: 60, points: 5)
        g.popMatrix()

        // 色相を更新
        hue += 0.01
    }

    func mousePressed(_ g: Graphics) {
        // クリックで頂点を追加
        points.append(SIMD2<Float>(g.mouseX, g.mouseY))
    }

    func keyPressed(_ g: Graphics) {
        // スペースキーでクリア
        if g.key == " " {
            points.removeAll()
        }
    }

    // 星形を描画するヘルパー
    private func drawStar(_ g: Graphics, cx: Float, cy: Float, radius1: Float, radius2: Float, points: Int) {
        g.fill(255, 200, 0)
        g.noStroke()

        g.beginShape()
        for i in 0..<(points * 2) {
            let angle = Float(i) * .pi / Float(points) - .pi / 2
            let r = (i % 2 == 0) ? radius2 : radius1
            g.vertex(cx + cos(angle) * r, cy + sin(angle) * r)
        }
        g.endShape(.close)
    }
}

// MARK: - beginShape/endShape Demo

/// 様々なShapeKindのデモ
struct ShapeKindDemo: View {
    var body: some View {
        sketch(width: 800, height: 600) { g in
            g.background(40)

            // TRIANGLES モード
            g.pushMatrix()
            g.translate(100, 100)
            g.fill(255, 100, 100)
            g.stroke(255)
            g.strokeWeight(1)
            g.beginShape(.triangles)
            g.vertex(0, 0)
            g.vertex(80, 0)
            g.vertex(40, 60)
            g.vertex(100, 0)
            g.vertex(180, 0)
            g.vertex(140, 60)
            g.endShape()
            g.popMatrix()

            // TRIANGLE_STRIP モード
            g.pushMatrix()
            g.translate(300, 100)
            g.fill(100, 255, 100)
            g.noStroke()
            g.beginShape(.triangleStrip)
            for i in 0..<8 {
                let x = Float(i) * 25
                let y: Float = (i % 2 == 0) ? 0 : 60
                g.vertex(x, y)
            }
            g.endShape()
            g.popMatrix()

            // TRIANGLE_FAN モード（扇形）
            g.pushMatrix()
            g.translate(600, 100)
            g.fill(100, 100, 255)
            g.noStroke()
            g.beginShape(.triangleFan)
            g.vertex(50, 50)  // 中心
            for i in 0...8 {
                let angle = Float(i) * .pi / 4
                g.vertex(50 + cos(angle) * 50, 50 + sin(angle) * 50)
            }
            g.endShape()
            g.popMatrix()

            // QUADS モード
            g.pushMatrix()
            g.translate(100, 250)
            g.fill(255, 255, 100)
            g.stroke(0)
            g.strokeWeight(2)
            g.beginShape(.quads)
            // 最初の四角形
            g.vertex(0, 0)
            g.vertex(60, 0)
            g.vertex(60, 60)
            g.vertex(0, 60)
            // 2番目の四角形
            g.vertex(80, 0)
            g.vertex(140, 0)
            g.vertex(140, 60)
            g.vertex(80, 60)
            g.endShape()
            g.popMatrix()

            // QUAD_STRIP モード
            g.pushMatrix()
            g.translate(300, 250)
            g.fill(255, 100, 255)
            g.noStroke()
            g.beginShape(.quadStrip)
            for i in 0..<5 {
                let x = Float(i) * 40
                let wobble = sin(Float(g.frameCount) * 0.05 + Float(i)) * 10
                g.vertex(x, wobble)
                g.vertex(x, 60 + wobble)
            }
            g.endShape()
            g.popMatrix()

            // LINES モード
            g.pushMatrix()
            g.translate(550, 250)
            g.stroke(100, 255, 255)
            g.strokeWeight(3)
            g.beginShape(.lines)
            for i in 0..<6 {
                let angle = Float(i) * .pi / 3
                g.vertex(50, 50)
                g.vertex(50 + cos(angle) * 40, 50 + sin(angle) * 40)
            }
            g.endShape()
            g.popMatrix()

            // POINTS モード
            g.pushMatrix()
            g.translate(700, 250)
            g.stroke(255)
            g.strokeWeight(5)
            g.beginShape(.points)
            for i in 0..<12 {
                let angle = Float(i) * .pi / 6
                g.vertex(30 + cos(angle) * 25, 30 + sin(angle) * 25)
            }
            g.endShape()
            g.popMatrix()

            // 自由な多角形（凹形状）
            g.pushMatrix()
            g.translate(100, 420)
            g.fill(200, 150, 255)
            g.stroke(255)
            g.strokeWeight(2)
            g.beginShape()
            // 星型の凹多角形
            let cx: Float = 80
            let cy: Float = 80
            for i in 0..<10 {
                let angle = Float(i) * .pi / 5 - .pi / 2
                let r: Float = (i % 2 == 0) ? 70 : 30
                g.vertex(cx + cos(angle) * r, cy + sin(angle) * r)
            }
            g.endShape(.close)
            g.popMatrix()

            // マウス追従する多角形
            g.pushMatrix()
            g.translate(g.mouseX, g.mouseY)
            g.rotate(Float(g.frameCount) * 0.03)
            g.fill(255, 255, 255, 150)
            g.stroke(255)
            g.strokeWeight(1)
            g.beginShape()
            for i in 0..<6 {
                let angle = Float(i) * .pi / 3
                g.vertex(cos(angle) * 30, sin(angle) * 30)
            }
            g.endShape(.close)
            g.popMatrix()
        }
    }
}

// MARK: - App Entry Point

@main
struct SketchDemoApp: App {
    @State private var showProtocolDemo = true

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                // タブ切り替えボタン
                HStack {
                    Button("Sketch Protocol") {
                        showProtocolDemo = true
                    }
                    .buttonStyle(.bordered)
                    .tint(showProtocolDemo ? .blue : .gray)

                    Button("Shape Kinds") {
                        showProtocolDemo = false
                    }
                    .buttonStyle(.bordered)
                    .tint(!showProtocolDemo ? .blue : .gray)

                    Spacer()

                    Text(showProtocolDemo ? "Click to add vertices, Space to clear" : "Various beginShape modes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color(white: 0.15))

                if showProtocolDemo {
                    SketchView(PolygonSketch())
                } else {
                    ShapeKindDemo()
                }
            }
        }
        .windowResizability(.contentSize)
    }
}
