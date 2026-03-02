import metaphor

@main final class ColorWheel: Sketch {
    var config: SketchConfig { SketchConfig(title: "Color Wheel") }

    func draw() {
        background(Color(gray: 0.05))

        let centerX = width / 2
        let centerY = height / 2
        let outerRadius: Float = min(width, height) * 0.42
        let innerRadius: Float = outerRadius * 0.25
        let steps = 360
        let angleStep = (2.0 * Float.pi) / Float(steps)
        let rotation = time * 0.3

        noStroke()

        // Draw color wheel using filled triangles
        for i in 0..<steps {
            let angle1 = Float(i) * angleStep + rotation
            let angle2 = Float(i + 1) * angleStep + rotation
            let hue = Float(i) / Float(steps)

            let color = Color(hue: hue, saturation: 1.0, brightness: 1.0)
            fill(color)

            let x1 = centerX + cos(angle1) * innerRadius
            let y1 = centerY + sin(angle1) * innerRadius
            let x2 = centerX + cos(angle1) * outerRadius
            let y2 = centerY + sin(angle1) * outerRadius
            let x3 = centerX + cos(angle2) * outerRadius
            let y3 = centerY + sin(angle2) * outerRadius

            triangle(x1, y1, x2, y2, x3, y3)

            // Second triangle to fill the quad
            let x4 = centerX + cos(angle2) * innerRadius
            let y4 = centerY + sin(angle2) * innerRadius
            triangle(x1, y1, x3, y3, x4, y4)
        }

        // Draw saturation gradient ring (inner portion fading to white)
        let gradientSteps = 20
        for j in 0..<gradientSteps {
            let satOuter = Float(j + 1) / Float(gradientSteps)
            let satInner = Float(j) / Float(gradientSteps)
            let rOuter = innerRadius * satOuter
            let rInner = innerRadius * satInner

            for i in 0..<steps {
                let angle1 = Float(i) * angleStep + rotation
                let angle2 = Float(i + 1) * angleStep + rotation
                let hue = Float(i) / Float(steps)

                let color = Color(hue: hue, saturation: satOuter, brightness: 1.0)
                fill(color)

                let ax = centerX + cos(angle1) * rInner
                let ay = centerY + sin(angle1) * rInner
                let bx = centerX + cos(angle1) * rOuter
                let by = centerY + sin(angle1) * rOuter
                let cx = centerX + cos(angle2) * rOuter
                let cy = centerY + sin(angle2) * rOuter

                triangle(ax, ay, bx, by, cx, cy)

                let dx = centerX + cos(angle2) * rInner
                let dy = centerY + sin(angle2) * rInner
                triangle(ax, ay, cx, cy, dx, dy)
            }
        }

        // White center dot
        fill(Color.white)
        circle(centerX, centerY, 8)
    }
}
