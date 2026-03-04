import metaphor

// NOTE: Original uses a GLSL blur filter shader applied via filter().
// This version approximates the visual effect using accumulated drawing.

@main
final class BlurFilter: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "BlurFilter")
    }

    func setup() {
        rectMode(.center)
        stroke(255, 0, 0)
    }

    func draw() {
        // Semi-transparent background for trail/blur effect
        fill(0, 0, 0, 15)
        noStroke()
        rect(width / 2, height / 2, width, height)

        stroke(255, 0, 0)
        fill(255, 0, 0, 60)
        rectMode(.center)
        rect(mouseX, mouseY, 150, 150)

        noStroke()
        fill(255, 0, 0, 40)
        ellipse(mouseX, mouseY, 100, 100)

        // Draw soft glow layers for blur approximation
        for i in 1...3 {
            let s = Float(i) * 8
            fill(255, 0, 0, Float(20 - i * 5))
            ellipse(mouseX, mouseY, 100 + s, 100 + s)
        }
    }
}
