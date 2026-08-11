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
