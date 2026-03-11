import metaphor

/// Syphon Output Demo
///
/// Renders an animated generative visual at 1920x1080 and publishes
/// every frame via Syphon. Open a Syphon client (e.g. MadMapper,
/// VDMX, Resolume, Simple Client) to receive the texture.
///
/// Key points:
/// - Set `syphonName` in SketchConfig to enable Syphon output
/// - The render loop automatically switches to timer mode for
///   reliable frame delivery even when the window is occluded
@main
final class SyphonOutputDemo: Sketch {
    var config: SketchConfig {
        SketchConfig(
            width: 1920,
            height: 1080,
            title: "Syphon Output",
            fps: 60,
            syphonName: "metaphor",
            windowScale: 0.5
        )
    }

    let ringCount = 12
    let segmentCount = 60

    func setup() {
        colorMode(.hsb, 360, 1, 1, 1)
    }

    func draw() {
        colorMode(.rgb, 255)
        background(10, 10, 15)
        colorMode(.hsb, 360, 1, 1, 1)

        translate(width / 2, height / 2)

        let t = Float(frameCount) * 0.008

        for ring in 0..<ringCount {
            let ringF = Float(ring)
            let baseRadius = 80 + ringF * 55
            let hueBase = (ringF / Float(ringCount)) * 360 + t * 30

            pushMatrix()
            rotate(t * (0.3 + ringF * 0.05) * (ring % 2 == 0 ? 1 : -1))

            for seg in 0..<segmentCount {
                let segF = Float(seg)
                let angle = (segF / Float(segmentCount)) * TWO_PI
                let nextAngle = ((segF + 1) / Float(segmentCount)) * TWO_PI

                let wave = sin(angle * 3 + t * (2 + ringF * 0.5)) * 30
                let pulse = sin(t * 1.5 + ringF * 0.4) * 15
                let r = baseRadius + wave + pulse

                let nextWave = sin(nextAngle * 3 + t * (2 + ringF * 0.5)) * 30
                let nextR = baseRadius + nextWave + pulse

                let x1 = cos(angle) * r
                let y1 = sin(angle) * r
                let x2 = cos(nextAngle) * nextR
                let y2 = sin(nextAngle) * nextR

                let hue = (hueBase + segF * 2).truncatingRemainder(dividingBy: 360)
                let brightness: Float = 0.6 + sin(angle * 5 + t * 3) * 0.4
                let alpha: Float = 0.15 + brightness * 0.35

                stroke(hue, 0.8, brightness, alpha)
                strokeWeight(1.5 + sin(t + ringF) * 0.8)
                line(x1, y1, x2, y2)

                if seg % 5 == 0 {
                    let dotR = r + 10 + sin(t * 2 + segF * 0.3) * 8
                    let dx = cos(angle) * dotR
                    let dy = sin(angle) * dotR
                    let dotSize = 2 + sin(t * 3 + segF) * 1.5

                    noStroke()
                    fill(hue, 0.8, brightness, min(alpha * 1.5, 1.0))
                    circle(dx, dy, dotSize)
                }
            }

            popMatrix()
        }

        // Center glow
        noStroke()
        for i in stride(from: 5, to: 0, by: -1) {
            let glowR = Float(i) * 18 + sin(t * 2) * 10
            let a: Float = 0.03 * Float(6 - i)
            let glowHue = (t * 50).truncatingRemainder(dividingBy: 360)
            fill(glowHue, 0.5, 1.0, a)
            circle(0, 0, glowR)
        }
    }
}
