import metaphor

@main
final class ShapePrimitives: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Shape Primitives")
    }

    func draw() {
        background(Color(gray: 0.85))

        // 矩形
        fill(Color(gray: 1.0))
        stroke(Color(gray: 0.0))
        strokeWeight(2)
        rect(60, 60, 200, 200)

        // 重なる長方形
        fill(Color(gray: 0.9))
        rect(200, 100, 400, 200)

        // 楕円（目の形）
        fill(Color(gray: 1.0))
        ellipse(1080, 200, 600, 200)

        // 瞳（円）
        fill(Color(gray: 0.1))
        circle(1120, 200, 200)

        // 弧（まぶた）
        noFill()
        stroke(Color(gray: 0.0))
        strokeWeight(3)
        arc(1080, 200, 600, 200, Float.pi, Float.pi * 2)

        // 直線
        stroke(Color(gray: 0.2))
        strokeWeight(3)
        line(60, 450, 400, 750)

        // 三角形
        fill(Color(gray: 0.7))
        stroke(Color(gray: 0.0))
        strokeWeight(2)
        triangle(500, 750, 700, 450, 900, 750)

        // 四角形（polygon）
        fill(Color(gray: 0.6))
        polygon([
            (1000, 550), (1100, 450), (1400, 600), (1300, 750)
        ])

        // ベジェ曲線
        noFill()
        stroke(Color(r: 0.8, g: 0.2, b: 0.2))
        strokeWeight(3)
        bezier(60, 900, 400, 700, 700, 1100, 1000, 900)

        // 点の列
        strokeWeight(6)
        stroke(Color(r: 0.2, g: 0.2, b: 0.8))
        for i in 0..<20 {
            let x: Float = 1100 + Float(i) * 40
            point(x, 900)
        }
    }
}
