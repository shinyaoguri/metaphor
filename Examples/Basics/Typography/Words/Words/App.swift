import metaphor

@main
final class Words: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Words") }
    func setup() {
        textFont("Menlo")
        textSize(18)
    }
    func draw() {
        background(102)
        textAlign(.right)
        drawType(width * 0.25)
        textAlign(.center)
        drawType(width * 0.5)
        textAlign(.left)
        drawType(width * 0.75)
    }
    private func drawType(_ x: Float) {
        stroke(255)
        line(x, 0, x, 65)
        line(x, 220, x, height)
        noStroke()
        fill(0)
        text("ichi", x, 95)
        fill(51)
        text("ni", x, 130)
        fill(204)
        text("san", x, 165)
        fill(255)
        text("shi", x, 210)
    }
}
