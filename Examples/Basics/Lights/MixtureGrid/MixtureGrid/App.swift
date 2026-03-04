import metaphor

@main
final class MixtureGrid: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Mixture Grid") }
    func setup() { noStroke() }
    func draw() {
        pointLight(200, -150, 0, color: Color(r: 150.0/255, g: 100.0/255, b: 0))
        directionalLight(1, 0, 0, color: Color(r: 0, g: 102.0/255, b: 1.0))
        spotLight(0, 40, 200, 0, -0.5, -0.5, angle: Float.pi / 2, color: Color(r: 1.0, g: 1.0, b: 109.0/255))
        background(0)
        var x: Float = 0
        while x <= width {
            var y: Float = 0
            while y <= height {
                push()
                translate(x, y, 0)
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
