import metaphor

@main
final class RotateExample: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Rotate")
    }

    func draw() {
        background(Color(gray: 0.85))

        let cols = 5
        let rows = 5
        let cellW = width / Float(cols)
        let cellH = height / Float(rows)
        let squareSize: Float = 60

        for row in 0..<rows {
            for col in 0..<cols {
                let x = cellW * (Float(col) + 0.5)
                let y = cellH * (Float(row) + 0.5)
                let speed = Float(row * cols + col + 1) * 0.3

                push()
                translate(x, y)
                rotate(time * speed)

                let hue = Float(row * cols + col) / Float(cols * rows)
                fill(Color(hue: hue, saturation: 0.6, brightness: 0.8))
                stroke(Color(gray: 0.2))
                strokeWeight(2)
                rect(-squareSize / 2, -squareSize / 2, squareSize, squareSize)
                pop()
            }
        }

        // 中央の大きな回転コンポジット
        push()
        translate(width / 2, height / 2)
        rotate(-time * 0.5)
        fill(Color(gray: 1.0, alpha: 0.7))
        stroke(Color(gray: 0.1))
        strokeWeight(3)
        rect(-75, -75, 150, 150)

        rotate(time * 1.5)
        fill(Color(gray: 0.2, alpha: 0.5))
        rect(-40, -40, 80, 80)
        pop()
    }
}
