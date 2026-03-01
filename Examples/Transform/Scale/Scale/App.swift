import metaphor

@main
final class ScaleExample: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Scale")
    }

    func draw() {
        background(Color(hue: 0.6, saturation: 0.1, brightness: 0.15))

        // 上: 脈動する円
        let circleCount = 5
        let spacing = width / Float(circleCount + 1)

        for i in 0..<circleCount {
            let x = spacing * Float(i + 1)
            let phase = Float(i) * 0.5
            let s = 0.5 + 0.5 * sin(time * 2.0 + phase)

            push()
            translate(x, 200)
            scale(s)
            fill(Color(hue: Float(i) / Float(circleCount), saturation: 0.7, brightness: 0.9, alpha: 0.8))
            noStroke()
            circle(0, 0, 80)
            pop()
        }

        // 中央: ネストしたスケーリング正方形
        push()
        translate(width / 2, height / 2)
        let layers = 8
        for i in (0..<layers).reversed() {
            let pulse = 0.8 + 0.2 * sin(time * 1.5 + Float(i) * 0.4)
            let layerScale = 1.0 - Float(i) * 0.1
            push()
            scale(pulse * layerScale)
            let hue = (Float(i) / Float(layers) + time * 0.05)
                .truncatingRemainder(dividingBy: 1.0)
            fill(Color(hue: hue, saturation: 0.5, brightness: 0.9, alpha: 0.4))
            stroke(Color(gray: 1.0, alpha: 0.3))
            strokeWeight(1)
            rect(-150, -150, 300, 300)
            pop()
        }
        pop()

        // 下: 非均一スケーリング
        let shapeCount = 4
        let bottomSpacing = width / Float(shapeCount + 1)
        for i in 0..<shapeCount {
            let x = bottomSpacing * Float(i + 1)
            let sx = 0.5 + 0.8 * sin(time * 1.2 + Float(i))
            let sy = 0.5 + 0.8 * cos(time * 1.2 + Float(i))
            push()
            translate(x, height - 150)
            scale(sx, sy)
            fill(Color(hue: 0.1 * Float(i) + 0.5, saturation: 0.6, brightness: 0.85, alpha: 0.8))
            stroke(Color(gray: 1.0, alpha: 0.5))
            strokeWeight(2)
            if i % 2 == 0 {
                rect(-30, -30, 60, 60)
            } else {
                ellipse(0, 0, 60, 60)
            }
            pop()
        }
    }
}
