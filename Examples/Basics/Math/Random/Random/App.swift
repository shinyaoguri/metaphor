import metaphor

@main
final class Random: Sketch {
    var config: SketchConfig { SketchConfig(title: "Random", width: 640, height: 360) }
    func setup() { background(0); strokeWeight(20); frameRate(2) }
    func draw() {
        for i in 0..<Int(width) {
            let r = random(255)
            stroke(r)
            line(Float(i), 0, Float(i), height)
        }
    }
}
