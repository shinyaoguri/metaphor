import metaphor

@main
final class Mixture: Sketch {
    var config: SketchConfig { SketchConfig(title: "Mixture", width: 640, height: 360) }
    func setup() { noStroke() }
    func draw() {
        background(0)
        translate3D(width / 2, height / 2, 0)
        pointLight(150, 100, 0, 200, -150, 0)
        directionalLight(0, 102, 255, 1, 0, 0)
        spotLight(255, 255, 109, 0, 40, 200, 0, -0.5, -0.5, Float.pi / 2, 2)
        rotateY(map(mouseX, 0, width, 0, Float.pi))
        rotateX(map(mouseY, 0, height, 0, Float.pi))
        box(150)
    }
}
