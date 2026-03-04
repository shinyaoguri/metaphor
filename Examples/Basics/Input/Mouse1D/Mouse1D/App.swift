import metaphor

@main
final class Mouse1D: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Mouse 1D") }
    func setup() {
        noStroke()
        colorMode(.rgb, height, height, height)
        rectMode(.center)
    }
    func draw() {
        background(0)
        let r1 = map(mouseX, 0, width, 0, height)
        let r2 = height - r1
        fill(r1)
        rect(width / 2 + r1 / 2, height / 2, r1, r1)
        fill(r2)
        rect(width / 2 - r2 / 2, height / 2, r2, r2)
    }
}
