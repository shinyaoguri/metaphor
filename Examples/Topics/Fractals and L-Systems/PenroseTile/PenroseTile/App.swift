import metaphor

@main
final class PenroseTile: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "PenroseTile", width: 640, height: 360)
    }

    var production = ""
    var drawLength: Float = 460.0
    var theta: Float = 0
    var steps = 0
    let ruleW = "YF++ZF4-XF[-YF4-WF]++"
    let ruleX = "+YF--ZF[3-WF--XF]+"
    let ruleY = "-WF++XF[+++YF++ZF]-"
    let ruleZ = "--YF++++WF[+ZF++++XF]--XF"

    func setup() {
        theta = radians(36)
        production = "[X]++[X]++[X]++[X]++[X]"
        drawLength = 460.0

        for _ in 0..<4 {
            var newProd = ""
            for ch in production {
                switch ch {
                case "W": newProd += ruleW
                case "X": newProd += ruleX
                case "Y": newProd += ruleY
                case "Z": newProd += ruleZ
                case "F": break  // remove standalone F during iteration
                default: newProd.append(ch)
                }
            }
            production = newProd
            drawLength *= 0.5
        }
    }

    func draw() {
        background(0)

        pushMatrix()
        translate(width / 2, height / 2)

        steps += 12
        if steps > production.count {
            steps = production.count
        }

        var pushes = 0
        var repeats = 1
        let chars = Array(production)

        for i in 0..<steps {
            let step = chars[i]
            if step == "F" {
                stroke(255, 60)
                noFill()
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
                pushes += 1
                pushMatrix()
            } else if step == "]" {
                popMatrix()
                pushes -= 1
            } else if let val = step.asciiValue, val >= 48 && val <= 57 {
                repeats = Int(val) - 48
            }
        }

        // Unpush if needed
        while pushes > 0 {
            popMatrix()
            pushes -= 1
        }

        popMatrix()
    }
}
