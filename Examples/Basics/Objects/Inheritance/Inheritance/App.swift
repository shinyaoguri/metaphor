import metaphor

class Spin {
    var x: Float; var y: Float; var speed: Float; var angle: Float = 0
    init(_ xpos: Float, _ ypos: Float, _ s: Float) { x = xpos; y = ypos; speed = s }
    func update() { angle += speed }
}

class SpinArm: Spin {
    override func update() { angle += speed }
}

class SpinSpots: Spin {
    var dim: Float
    init(_ xpos: Float, _ ypos: Float, _ s: Float, _ d: Float) {
        dim = d; super.init(xpos, ypos, s)
    }
    override func update() { angle += speed }
}

@main
final class Inheritance: Sketch {
    var arm: SpinArm!; var spots: SpinSpots!
    var config: SketchConfig { SketchConfig(title: "Inheritance", width: 640, height: 360) }
    func setup() {
        arm = SpinArm(width / 2, height / 2, 0.01)
        spots = SpinSpots(width / 2, height / 2, -0.02, 90)
    }
    func draw() {
        background(204)
        arm.update()
        strokeWeight(1); stroke(0)
        push()
        translate(arm.x, arm.y); rotate(arm.angle)
        line(0, 0, 165, 0)
        pop()
        spots.update()
        noStroke()
        push()
        translate(spots.x, spots.y); rotate(spots.angle)
        ellipse(-spots.dim / 2, 0, spots.dim, spots.dim)
        ellipse(spots.dim / 2, 0, spots.dim, spots.dim)
        pop()
    }
}
