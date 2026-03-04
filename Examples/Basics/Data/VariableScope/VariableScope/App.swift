import metaphor

@main
final class VariableScope: Sketch {
    let a: Float = 80

    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Variable Scope") }

    func setup() {
        background(0)
        stroke(255)
        noLoop()
    }

    func draw() {
        // Draw a line using the global variable "a"
        line(a, 0, a, height)

        // Local loop variable
        var i: Float = 120
        while i < 200 {
            line(i, 0, i, height)
            i += 2
        }

        // Local variable shadows the property
        let localA: Float = 300
        line(localA, 0, localA, height)

        drawAnotherLine()
        drawYetAnotherLine()
    }

    private func drawAnotherLine() {
        let localA: Float = 320
        line(localA, 0, localA, height)
    }

    private func drawYetAnotherLine() {
        // Uses the property "a" (80)
        line(a + 2, 0, a + 2, height)
    }
}
