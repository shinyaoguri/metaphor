import metaphor

@main
final class Perspective: Sketch {
    var config: SketchConfig { SketchConfig(title: "Perspective", width: 640, height: 360) }
    func setup() { noStroke() }
    func draw() {
        ambientLight(128, 128, 128)
        directionalLight(128, 128, 128, 0, 0, -1)
        background(0)
        let cameraY = height / 2
        let fov = mouseX / width * Float.pi / 2
        let cameraZ = cameraY / tan(fov / 2)
        var aspect = width / height
        if isMousePressed { aspect = aspect / 2 }
        perspective(fov, aspect, cameraZ / 10, cameraZ * 10)
        translate3D(width / 2 + 30, height / 2, 0)
        rotateX(-Float.pi / 6)
        rotateY(Float.pi / 3 + mouseY / height * Float.pi)
        box(45)
        translate3D(0, 0, -50)
        box(30)
    }
}
