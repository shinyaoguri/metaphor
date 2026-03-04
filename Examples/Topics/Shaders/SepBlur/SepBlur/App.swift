import metaphor

// NOTE: Original uses a two-pass GLSL separable blur shader.
// This version approximates the blur using multiple concentric circles.

@main
final class SepBlur: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "SepBlur", width: 640, height: 360)
    }

    var blurSize = 9

    func setup() {
        noStroke()
    }

    func draw() {
        background(0)

        // Draw a blurred circle using multiple semi-transparent layers
        let cx = width / 2
        let cy = height / 2
        let baseRadius: Float = 50

        // Gaussian-like falloff
        let layers = blurSize * 3
        for i in (0...layers).reversed() {
            let t = Float(i) / Float(layers)
            let radius = baseRadius + Float(blurSize) * t * 3
            let alpha = (1.0 - t) * 255.0 / Float(layers) * 8
            fill(255, max(1, alpha))
            ellipse(cx, cy, radius * 2, radius * 2)
        }

        // Sharp center
        fill(255, 200)
        ellipse(cx, cy, baseRadius * 2, baseRadius * 2)
    }

    func keyPressed() {
        if key == "9" { blurSize = 9 }
        else if key == "7" { blurSize = 7 }
        else if key == "5" { blurSize = 5 }
        else if key == "3" { blurSize = 3 }
    }
}
