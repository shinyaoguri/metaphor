import metaphor

@main
final class Arm: Sketch {
    var x: Float = 0
    var y: Float = 0
    let segLength: Float = 100
    var config: SketchConfig { SketchConfig(title: "Arm", width: 640, height: 360) }
    func setup() {
        strokeWeight(30)
        stroke(255, 160)
        x = width * 0.3
        y = height * 0.5
    }
    func draw() {
        background(0)
        let angle1 = (mouseX / width - 0.5) * -Float.pi
        let angle2 = (mouseY / height - 0.5) * Float.pi
        push()
        segment(x, y, angle1)
        segment(segLength, 0, angle2)
        pop()
    }
    private func segment(_ x: Float, _ y: Float, _ a: Float) {
        translate(x, y)
        rotate(a)
        line(0, 0, segLength, 0)
    }
}
