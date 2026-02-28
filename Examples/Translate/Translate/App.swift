import metaphor

@main
final class TranslateExample: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Translate")
    }

    func draw() {
        background(Color(gray: 0.85))

        let t = time

        strokeWeight(2)
        stroke(Color(gray: 0.3))

        // 左: translate なしの絶対座標
        fill(Color(r: 0.9, g: 0.3, b: 0.3, a: 0.6))
        rect(100, 200, 120, 120)
        rect(100, 400, 120, 120)
        rect(100, 600, 120, 120)

        // 中央: translate で配置
        for i in 0..<5 {
            let fi = Float(i)
            let offsetY = sin(t + fi * 0.5) * 40

            push()
            translate(500 + fi * 180, 300 + offsetY)
            fill(Color(hue: fi / 5.0, saturation: 0.6, brightness: 0.9))
            rect(-60, -60, 120, 120)
            pop()
        }

        // 下: ネストした translate
        push()
        translate(width * 0.5, 700)
        for i in 0..<8 {
            translate(100, 0)
            let fi = Float(i)
            let bounce = sin(t * 2 + fi * 0.4) * 30
            push()
            translate(0, bounce)
            fill(Color(hue: fi / 8.0, saturation: 0.5, brightness: 1.0))
            noStroke()
            circle(0, 0, 60)
            pop()
        }
        pop()
    }
}
