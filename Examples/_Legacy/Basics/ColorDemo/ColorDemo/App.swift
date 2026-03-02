import metaphor

@main
final class ColorDemo: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Color")
    }

    func draw() {
        background(Color(r: 0.27, g: 0.51, b: 0.71))

        strokeWeight(4)

        // 白い正方形 + 暗い青ストローク
        fill(Color(r: 0.78, g: 0.78, b: 1.0))
        stroke(Color(r: 0.08, g: 0.08, b: 0.4))
        rect(60, 60, 200, 200)

        // 長方形（同じfill色を引き継ぐ）
        stroke(Color(r: 0.4, g: 0.08, b: 0.08))
        rect(200, 100, 400, 200)

        // 緑の楕円（HSBカラー）
        fill(Color(hue: 0.33, saturation: 0.7, brightness: 0.9))
        stroke(Color(hue: 0.33, saturation: 0.6, brightness: 0.3))
        ellipse(1080, 200, 600, 200)

        // 暗いフューシャ円（ストロークなし）
        fill(Color(hue: 0.83, saturation: 0.9, brightness: 0.3))
        noStroke()
        circle(1120, 200, 200)

        // 明るい緑の弧
        fill(Color(hue: 0.33, saturation: 0.7, brightness: 0.9))
        stroke(Color(hue: 0.33, saturation: 0.6, brightness: 0.3))
        strokeWeight(4)
        arc(1080, 200, 600, 200, Float.pi, Float.pi * 2)

        // ネイビーの線
        stroke(Color(r: 0.08, g: 0.04, b: 0.31))
        strokeWeight(3)
        line(60, 450, 400, 750)

        // HSBカラーの三角形
        fill(Color(hue: 0.33, saturation: 0.7, brightness: 0.9))
        stroke(Color(hue: 0.33, saturation: 0.6, brightness: 0.3))
        strokeWeight(4)
        triangle(500, 750, 700, 450, 900, 750)

        // ストロークのみのquad
        noFill()
        stroke(Color(r: 0.94, g: 0.85, b: 0.85))
        strokeWeight(4)
        polygon([
            (1000, 550), (1100, 450), (1400, 600), (1300, 750)
        ])

        // グラデーション帯（色の補間デモ）
        let y: Float = 850
        let h: Float = 120
        let steps = 60
        let c1 = Color(hue: 0.0, saturation: 0.8, brightness: 1.0)
        let c2 = Color(hue: 0.6, saturation: 0.8, brightness: 1.0)
        noStroke()
        for i in 0..<steps {
            let t = Float(i) / Float(steps)
            let c = c1.lerp(to: c2, t: t)
            let x = 60 + Float(i) * (1800 / Float(steps))
            fill(c)
            rect(x, y, 1800 / Float(steps) + 1, h)
        }
    }
}
