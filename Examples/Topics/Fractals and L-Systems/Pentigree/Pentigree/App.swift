import metaphor

@main
final class Pentigree: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Pentigree", width: 640, height: 360)
    }

    var production = ""
    var drawLength: Float = 60.0
    var theta: Float = 0
    var steps = 0

    func setup() {
        theta = radians(72)
        production = "F-F-F-F-F"
        drawLength = 60.0
        let rule = "F-F++F+F-F-F"

        for _ in 0..<3 {
            production = production.replacingOccurrences(of: "F", with: rule)
            drawLength *= 0.6
        }
    }

    func draw() {
        background(0)

        pushMatrix()
        translate(width / 4, height / 2)

        steps += 3
        if steps > production.count {
            steps = production.count
        }

        let chars = Array(production)
        for i in 0..<steps {
            let step = chars[i]
            if step == "F" {
                noFill()
                stroke(255)
                line(0, 0, 0, -drawLength)
                translate(0, -drawLength)
            } else if step == "+" {
                rotate(theta)
            } else if step == "-" {
                rotate(-theta)
            } else if step == "[" {
                pushMatrix()
            } else if step == "]" {
                popMatrix()
            }
        }

        popMatrix()
    }
}
