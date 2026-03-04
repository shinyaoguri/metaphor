import metaphor

@main
final class EmbeddedIteration: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Embedding Iteration") }
    func setup() { noLoop() }
    func draw() {
        background(0)
        let gridSize: Float = 40
        var x = gridSize
        while x <= width - gridSize {
            var y = gridSize
            while y <= height - gridSize {
                noStroke()
                fill(255)
                rect(x - 1, y - 1, 3, 3)
                stroke(255, 100)
                line(x, y, width / 2, height / 2)
                y += gridSize
            }
            x += gridSize
        }
    }
}
