import metaphor

@main
final class TextRendering: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "TextRendering", width: 800, height: 600)
    }

    func setup() {
        fill(0)
    }

    func draw() {
        background(255)
        for _ in 0..<2000 {
            let x = Float.random(in: 0...width)
            let y = Float.random(in: 0...height)
            text("HELLO", x, y)
        }
        if frameCount % 10 == 0 { print("fps: \(Int(1.0 / deltaTime))") }
    }
}
