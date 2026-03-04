import metaphor

@main
final class Bounce: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Bounce")
    }

    let rad: Float = 60
    var xpos: Float = 0
    var ypos: Float = 0
    let xspeed: Float = 2.8
    let yspeed: Float = 2.2
    var xdirection: Float = 1
    var ydirection: Float = 1

    func setup() {
        noStroke()
        xpos = width / 2
        ypos = height / 2
    }

    func draw() {
        background(102)
        xpos += xspeed * xdirection
        ypos += yspeed * ydirection
        if xpos > width - rad || xpos < rad { xdirection *= -1 }
        if ypos > height - rad || ypos < rad { ydirection *= -1 }
        ellipse(xpos, ypos, rad * 2, rad * 2)
    }
}
