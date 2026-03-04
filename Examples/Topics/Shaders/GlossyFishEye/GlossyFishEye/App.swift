import metaphor

// NOTE: Original uses GLSL fish-eye + glossy shaders.
// This version renders a grid of spheres with simplified lighting.

@main
final class GlossyFishEye: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 640, title: "GlossyFishEye")
    }

    var useFishEye = true

    func setup() {
        noStroke()
    }

    func draw() {
        background(0)

        // Rotating light
        let lightX = 1000 * cos(Float(frameCount) * 0.01)
        let lightZ = 1000 * sin(Float(frameCount) * 0.01)
        pointLight(lightX, 1000, lightZ, color: Color(r: 0.8, g: 0.8, b: 0.8))

        fill(230, 50, 50)

        if useFishEye {
            // Fish-eye approximation: scale objects towards center
            let cx = width / 2
            let cy = height / 2

            for x in stride(from: Float(0), to: width + 100, by: 100) {
                for y in stride(from: Float(0), to: height + 100, by: 100) {
                    for z in stride(from: Float(0), to: 400, by: 100) {
                        let dx = x - cx
                        let dy = y - cy
                        let d = sqrt(dx * dx + dy * dy) / (width / 2)
                        let fishScale = 1.0 + d * d * 0.3 // Barrel distortion

                        pushMatrix()
                        translate(cx + dx * fishScale, cy + dy * fishScale, -z)
                        sphere(25 * (1.0 + d * 0.2))
                        popMatrix()
                    }
                }
            }
        } else {
            for x in stride(from: Float(0), to: width + 100, by: 100) {
                for y in stride(from: Float(0), to: height + 100, by: 100) {
                    for z in stride(from: Float(0), to: 400, by: 100) {
                        pushMatrix()
                        translate(x, y, -z)
                        sphere(25)
                        popMatrix()
                    }
                }
            }
        }
    }

    func mousePressed() {
        useFishEye = !useFishEye
    }
}
