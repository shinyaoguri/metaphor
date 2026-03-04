import metaphor

@main
final class Iteration: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Iteration") }
    func setup() { noLoop() }
    func draw() {
        background(102)
        noStroke()
        let num = 14

        // White bars
        fill(255)
        var y: Float = 60
        for _ in 0..<(num / 3) {
            rect(50, y, 475, 10)
            y += 20
        }

        // Gray bars
        fill(51)
        y = 40
        for _ in 0..<num {
            rect(405, y, 30, 10)
            y += 20
        }
        y = 50
        for _ in 0..<num {
            rect(425, y, 30, 10)
            y += 20
        }

        // Thin lines
        y = 45
        fill(0)
        for _ in 0..<(num - 1) {
            rect(120, y, 40, 1)
            y += 20
        }
    }
}
