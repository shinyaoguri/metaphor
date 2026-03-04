import metaphor

@main
final class MixtureGrid: Sketch {
    var config: SketchConfig { SketchConfig(title: "Mixture Grid", width: 640, height: 360) }
    func setup() { noStroke() }
    func draw() {
        pointLight(150, 100, 0, 200, -150, 0)
        directionalLight(0, 102, 255, 1, 0, 0)
        spotLight(255, 255, 109, 0, 40, 200, 0, -0.5, -0.5, Float.pi / 2, 2)
        background(0)
        var x: Float = 0
        while x <= width {
            var y: Float = 0
            while y <= height {
                push()
                translate3D(x, y, 0)
                rotateY(map(mouseX, 0, width, 0, Float.pi))
                rotateX(map(mouseY, 0, height, 0, Float.pi))
                box(90)
                pop()
                y += 60
            }
            x += 60
        }
    }
}
