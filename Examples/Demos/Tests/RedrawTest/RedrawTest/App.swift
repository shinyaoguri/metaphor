import metaphor

@main
final class RedrawTest: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "RedrawTest", width: 400, height: 400)
    }

    func setup() {
        noLoop()
    }

    func draw() {
        background(255, 0, 0)
        ellipse(mouseX, mouseY, 100, 50)
        print("draw")
    }

    func keyPressed() {
        redraw()
    }
}
