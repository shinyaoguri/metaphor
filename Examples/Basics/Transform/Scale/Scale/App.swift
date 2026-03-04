import metaphor

@main
final class Scale: Sketch {
    var a: Float = 0
    var s: Float = 0
    var config: SketchConfig { SketchConfig(title: "Scale", width: 640, height: 360) }
    func setup() {
        noStroke()
        rectMode(.center)
        frameRate(30)
    }
    func draw() {
        background(102)
        a += 0.04
        s = cos(a) * 2
        translate(width / 2, height / 2)
        scale(s)
        fill(51)
        rect(0, 0, 50, 50)
        translate(75, 0)
        fill(255)
        scale(s)
        rect(0, 0, 50, 50)
    }
}
