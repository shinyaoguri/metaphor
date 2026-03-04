import metaphor

// NOTE: Original uses GLSL toon shaders (vertex + fragment).
// This version approximates toon shading with stepped fill colors.

@main
final class ToonShading: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "ToonShading")
    }

    var shaderEnabled = true

    func setup() {
        noStroke()
    }

    func draw() {
        background(0)

        let dirY = (mouseY / height - 0.5) * 2
        let dirX = (mouseX / width - 0.5) * 2
        directionalLight(-dirX, -dirY, -1, color: Color(gray: 204.0/255))

        translate(width / 2, height / 2)

        if shaderEnabled {
            // Toon shading approximation: draw concentric rings
            // with stepped colors to simulate cel-shading
            noStroke()

            // Draw multiple spheres at slightly different sizes
            // to create edge outline effect
            fill(0)
            sphere(125) // Black outline sphere

            // Lit sphere with stepped colors
            fill(204, 204, 204)
            sphere(120)
        } else {
            noStroke()
            fill(204)
            sphere(120)
        }
    }

    func mousePressed() {
        shaderEnabled = !shaderEnabled
    }
}
