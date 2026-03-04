import metaphor

@main
final class Reflection: Sketch {
    var config: SketchConfig { SketchConfig(title: "Reflection", width: 640, height: 360) }
    func setup() { noStroke(); fill(102) }
    func draw() {
        background(0)
        translate3D(width / 2, height / 2, 0)
        directionalLight(204, 204, 204, 0, 0, -1)
        let s = mouseX / width
        specular(s, s, s)
        sphere(120)
    }
}
