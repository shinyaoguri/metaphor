import metaphor

@main
final class QuadRendering: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 800, height: 600, title: "QuadRendering")
    }

    func setup() {
        noStroke()
        fill(0, 1)
    }

    func draw() {
        background(255)
        for _ in 0..<10000 {
            let x = Float.random(in: 0...width)
            let y = Float.random(in: 0...height)
            rect(x, y, 30, 30)
        }
        if frameCount % 10 == 0 { print("fps: \(Int(1.0 / deltaTime))") }
    }
}
