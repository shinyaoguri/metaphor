import metaphor

@main
final class MousePress: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Mouse Press") }
    func setup() {
        fill(126)
        background(102)
    }
    func draw() {
        if isMousePressed {
            stroke(255)
        } else {
            stroke(0)
        }
        line(mouseX - 66, mouseY, mouseX + 66, mouseY)
        line(mouseX, mouseY - 66, mouseX, mouseY + 66)
    }
}
