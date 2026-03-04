import metaphor

class Eye {
    var x: Float
    var y: Float
    var size: Float
    var angle: Float = 0
    init(_ tx: Float, _ ty: Float, _ ts: Float) { x = tx; y = ty; size = ts }
    func update(_ mx: Float, _ my: Float) { angle = atan2(my - y, mx - x) }
}

@main
final class Arctangent: Sketch {
    var e1: Eye!
    var e2: Eye!
    var e3: Eye!
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Arctangent") }
    func setup() {
        noStroke()
        e1 = Eye(250, 16, 120)
        e2 = Eye(164, 185, 80)
        e3 = Eye(420, 230, 220)
    }
    func draw() {
        background(102)
        for e in [e1!, e2!, e3!] {
            e.update(mouseX, mouseY)
            push()
            translate(e.x, e.y)
            fill(255)
            ellipse(0, 0, e.size, e.size)
            rotate(e.angle)
            fill(153, 204, 0)
            ellipse(e.size / 4, 0, e.size / 2, e.size / 2)
            pop()
        }
    }
}
