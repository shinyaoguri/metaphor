import metaphor

@main
final class Perspective: Sketch {
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Perspective") }
    func setup() { noStroke() }
    func draw() {
        ambientLight(128, 128, 128)
        directionalLight(0, 0, -1, color: Color(gray: 128.0/255))
        background(0)
        let cameraY = height / 2
        let fov = mouseX / width * Float.pi / 2
        let cameraZ = cameraY / tan(fov / 2)
        perspective(fov: fov, near: cameraZ / 10, far: cameraZ * 10)
        translate(width / 2 + 30, height / 2, 0)
        rotateX(-Float.pi / 6)
        rotateY(Float.pi / 3 + mouseY / height * Float.pi)
        box(45)
        translate(0, 0, -50)
        box(30)
    }
}
