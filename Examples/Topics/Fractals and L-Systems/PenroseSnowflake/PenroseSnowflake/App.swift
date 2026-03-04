import metaphor

@main
final class PenroseSnowflake: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "PenroseSnowflake")
    }

    var production = ""
    var drawLength: Float = 450.0
    var theta: Float = 0
    var steps = 0
    let ruleF = "F3-F3-F45-F++F3-F"

    func setup() {
        stroke(255)
        noFill()

        theta = radians(18)

        // Build production string
        production = "F3-F3-F3-F3-F"
        drawLength = 450.0

        // simulate 4 generations
        for _ in 0..<4 {
            var newProd = ""
            for ch in production {
                if ch == "F" {
                    newProd += ruleF
                } else {
                    newProd.append(ch)
                }
            }
            production = newProd
            drawLength *= 0.4
        }
    }

    func draw() {
        background(0)

        pushMatrix()
        translate(width, height)

        steps += 3
        if steps > production.count {
            steps = production.count
        }

        var repeats = 1
        let chars = Array(production)
        for i in 0..<steps {
            let step = chars[i]
            if step == "F" {
                for _ in 0..<repeats {
                    line(0, 0, 0, -drawLength)
                    translate(0, -drawLength)
                }
                repeats = 1
            } else if step == "+" {
                for _ in 0..<repeats {
                    rotate(theta)
                }
                repeats = 1
            } else if step == "-" {
                for _ in 0..<repeats {
                    rotate(-theta)
                }
                repeats = 1
            } else if step == "[" {
                pushMatrix()
            } else if step == "]" {
                popMatrix()
            } else if let val = step.asciiValue, val >= 48 && val <= 57 {
                repeats += Int(val) - 48
            }
        }

        popMatrix()
    }
}
