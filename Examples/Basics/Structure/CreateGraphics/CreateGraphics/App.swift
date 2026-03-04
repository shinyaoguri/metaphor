import metaphor

@main
final class CreateGraphics: Sketch {
    var pg: Graphics!
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Create Graphics") }
    func setup() {
        pg = createGraphics(400, 200)
    }
    func draw() {
        fill(0, 12)
        rect(0, 0, width, height)
        fill(255)
        noStroke()
        ellipse(mouseX, mouseY, 60, 60)
        pg.beginDraw()
        pg.background(51)
        pg.noFill()
        pg.stroke(255)
        pg.ellipse(mouseX - 120, mouseY - 60, 60, 60)
        pg.endDraw()
        image(pg, 120, 60)
    }
}
