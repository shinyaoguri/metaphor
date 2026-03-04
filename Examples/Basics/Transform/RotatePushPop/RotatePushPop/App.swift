import metaphor

@main
final class RotatePushPop: Sketch {
    var a: Float = 0
    let offset = Float.pi / 24
    let num = 12
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Rotate Push Pop") }
    func setup() {
        noStroke()
    }
    func draw() {
        ambientLight(128, 128, 128)
        directionalLight(0, 0, -1, color: Color(gray: 128.0/255))
        background(0, 0, 26)
        translate(width / 2, height / 2, 0)
        for i in 0..<num {
            let gray = map(Float(i), 0, Float(num - 1), 0, 255)
            push()
            fill(gray)
            rotateY(a + offset * Float(i))
            rotateX(a / 2 + offset * Float(i))
            box(200)
            pop()
        }
        a += 0.01
    }
}
