import metaphor

// Processing original: https://github.com/processing/processing-examples/tree/main/Basics/Lights/Reflection
// The original .pde is not bundled — see Examples/NOTICE.md.

@main
final class Reflection: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Reflection") }
    func setup() { noStroke(); fill(102) }
    func draw() {
        background(0)
        translate(width / 2, height / 2, 0)
        directionalLight(0, 0, -1, color: Color(gray: 204.0/255))
        let s = mouseX / width
        specular(s)
        sphere(120)
    }
}
