import metaphor

@main
final class LineRendering: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "LineRendering", width: 800, height: 600)
    }

    func setup() {}

    func draw() {
        background(255)
        stroke(0, 10)
        for _ in 0..<10000 {
            let x0 = Float.random(in: 0...width)
            let y0 = Float.random(in: 0...height)
            let x1 = Float.random(in: 0...width)
            let y1 = Float.random(in: 0...height)
            line(x0, y0, x1, y1)
        }
        if frameCount % 10 == 0 { print("fps: \(Int(1.0 / deltaTime))") }
    }
}
