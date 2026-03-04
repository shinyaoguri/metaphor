import metaphor

@main
final class TextRotation: Sketch {
    var angleRotate: Float = 0
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Text Rotation") }
    func setup() {
        background(0)
        textFont("Menlo")
        textSize(18)
    }
    func draw() {
        background(0)
        fill(255)

        strokeWeight(1)
        stroke(153)

        push()
        let angle1 = radians(45)
        translate(100, 180)
        rotate(angle1)
        text("45 DEGREES", 0, 0)
        line(0, 0, 150, 0)
        pop()

        push()
        let angle2 = radians(270)
        translate(200, 180)
        rotate(angle2)
        text("270 DEGREES", 0, 0)
        line(0, 0, 150, 0)
        pop()

        push()
        translate(440, 180)
        rotate(radians(angleRotate))
        text("\(Int(angleRotate) % 360) DEGREES", 0, 0)
        line(0, 0, 150, 0)
        pop()

        angleRotate += 0.25

        stroke(255, 0, 0)
        strokeWeight(4)
        point(100, 180)
        point(200, 180)
        point(440, 180)
    }
}
