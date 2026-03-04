import metaphor

@main
final class Milliseconds: Sketch {
    var s: Float = 0
    var config: SketchConfig { SketchConfig(width: 640, height: 360, title: "Milliseconds") }
    func setup() {
        noStroke()
        s = width / 20
    }
    func draw() {
        let millis = Int(time * 1000)
        for i in 0..<Int(s) {
            colorMode(.rgb, Float(i + 1) * s * 10)
            fill(Float(millis % Int(Float(i + 1) * s * 10)))
            rect(Float(i) * s, 0, s, height)
        }
    }
}
