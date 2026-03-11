import metaphor

/// Syphon Triple Window Demo
///
/// Three FHD windows, each publishing to a separate Syphon server:
/// - "metaphor - A" : Morphing wireframe sphere (3D)
/// - "metaphor - B" : Kaleidoscope pattern (2D)
/// - "metaphor - C" : Waveform visualizer (2D)
///
/// All three share timing so visuals stay in sync.
@main
final class SyphonTripleWindow: Sketch {
    var config: SketchConfig {
        SketchConfig(
            width: 1920,
            height: 1080,
            title: "Syphon A - Wireframe",
            fps: 60,
            syphonName: "metaphor - A",
            windowScale: 0.35
        )
    }

    var winB: SketchWindow?
    var winC: SketchWindow?

    func setup() {
        winB = createWindow(SketchWindowConfig(
            width: 1920, height: 1080,
            title: "Syphon B - Kaleidoscope",
            fps: 60, windowScale: 0.35,
            syphonName: "metaphor - B"
        ))
        winC = createWindow(SketchWindowConfig(
            width: 1920, height: 1080,
            title: "Syphon C - Waveform",
            fps: 60, windowScale: 0.35,
            syphonName: "metaphor - C"
        ))
    }

    func draw() {
        let t = Float(frameCount) * 0.01

        // === Window A: Morphing wireframe sphere ===
        drawWindowA(t)

        // === Window B: Kaleidoscope ===
        winB?.draw { ctx in
            Self.drawWindowB(ctx: ctx, t: t)
        }

        // === Window C: Waveform ===
        winC?.draw { ctx in
            Self.drawWindowC(ctx: ctx, t: t)
        }
    }

    // MARK: - Window A: Morphing wireframe sphere

    func drawWindowA(_ t: Float) {
        background(8, 8, 16)
        translate(width / 2, height / 2)

        let rings = 20
        let segments = 40
        let baseR: Float = 300

        for i in 0..<rings {
            let phi = Float(i) / Float(rings) * PI
            for j in 0..<segments {
                let theta = Float(j) / Float(segments) * TWO_PI
                let nextTheta = Float(j + 1) / Float(segments) * TWO_PI

                let deform = sin(phi * 3 + t * 2) * cos(theta * 2 + t * 1.5) * 60
                let r = baseR + deform

                let x1 = r * sin(phi) * cos(theta)
                let y1 = r * cos(phi)
                let z1 = r * sin(phi) * sin(theta)

                let deform2 = sin(phi * 3 + t * 2) * cos(nextTheta * 2 + t * 1.5) * 60
                let r2 = baseR + deform2

                let x2 = r2 * sin(phi) * cos(nextTheta)
                let y2 = r2 * cos(phi)
                let z2 = r2 * sin(phi) * sin(nextTheta)

                // Project 3D to 2D (simple perspective)
                let fov: Float = 800
                let scale1 = fov / (fov + z1 * cos(t * 0.3) + x1 * sin(t * 0.3))
                let scale2 = fov / (fov + z2 * cos(t * 0.3) + x2 * sin(t * 0.3))

                let sx1 = (x1 * cos(t * 0.3) - z1 * sin(t * 0.3)) * scale1
                let sy1 = y1 * scale1
                let sx2 = (x2 * cos(t * 0.3) - z2 * sin(t * 0.3)) * scale2
                let sy2 = y2 * scale2

                let depth = (scale1 + scale2) * 0.5
                let alpha = depth * depth * 180
                let hue = (Float(i) / Float(rings) * 180 + t * 15)
                    .truncatingRemainder(dividingBy: 360)

                colorMode(.hsb, 360, 255, 255, 255)
                stroke(hue, 200, 255, alpha)
                strokeWeight(0.8 + depth * 0.5)
                line(sx1, sy1, sx2, sy2)
            }
        }
    }

    // MARK: - Window B: Kaleidoscope

    static func drawWindowB(ctx: SketchContext, t: Float) {
        ctx.background(5, 5, 10)
        ctx.translate(960, 540)

        let symmetry = 8
        let angleStep = TWO_PI / Float(symmetry)

        for s in 0..<symmetry {
            ctx.pushMatrix()
            ctx.rotate(angleStep * Float(s))

            let layers = 6
            for layer in 0..<layers {
                let layerF = Float(layer)
                let offset = layerF * 70 + 50
                let count = 12 + layer * 4

                for i in 0..<count {
                    let iF = Float(i)
                    let angle = iF / Float(count) * PI * 0.4 - 0.2
                    let dist = offset + sin(t * (1.5 + layerF * 0.3) + iF * 0.5) * 30

                    let x = cos(angle) * dist
                    let y = sin(angle) * dist

                    let size = 4 + sin(t * 2 + iF + layerF) * 3
                    let hue = (layerF * 50 + iF * 8 + t * 25)
                        .truncatingRemainder(dividingBy: 360)
                    let bright: Float = 200 + sin(t * 3 + iF * 0.7) * 55

                    ctx.colorMode(.hsb, 360, 255, 255, 255)
                    ctx.noStroke()
                    ctx.fill(hue, 220, bright, 180)
                    ctx.circle(x, y, size)
                }
            }

            ctx.popMatrix()
        }

        // Center ornament
        ctx.colorMode(.rgb, 255)
        ctx.noStroke()
        for i in stride(from: 4, to: 0, by: -1) {
            let r = Float(i) * 12 + sin(t * 2) * 5
            let v: Float = 200 + Float(4 - i) * 14
            ctx.fill(v, v, 255, 120)
            ctx.circle(0, 0, r)
        }
    }

    // MARK: - Window C: Waveform visualizer

    static func drawWindowC(ctx: SketchContext, t: Float) {
        ctx.background(12, 8, 18)

        let w: Float = 1920
        let h: Float = 1080
        let cy = h / 2

        // Draw multiple layered waveforms
        let waveCount = 5
        for wave in 0..<waveCount {
            let waveF = Float(wave)
            let yOffset = cy + (waveF - Float(waveCount) / 2) * 120

            let freq = 2 + waveF * 0.7
            let amp = 80 - waveF * 8
            let phase = t * (1.5 + waveF * 0.4)

            let hue = (waveF * 60 + t * 20).truncatingRemainder(dividingBy: 360)

            // Filled wave band
            ctx.colorMode(.hsb, 360, 255, 255, 255)
            ctx.noStroke()
            ctx.fill(hue, 180, 230, 40)

            ctx.beginShape(.triangleStrip)
            let step: Float = 4
            var x: Float = 0
            while x <= w {
                let normalX = x / w
                let y1 = sin(normalX * freq * TWO_PI + phase) * amp
                let y2 = sin(normalX * freq * TWO_PI + phase + 0.5) * amp * 0.6

                // Envelope to fade edges
                let envelope = sin(normalX * PI)

                ctx.vertex(x, yOffset + y1 * envelope)
                ctx.vertex(x, yOffset + y2 * envelope + amp * 0.8)
                x += step
            }
            ctx.endShape()

            // Bright line on top
            ctx.stroke(hue, 200, 255, 200)
            ctx.strokeWeight(1.5)
            ctx.noFill()
            ctx.beginShape()
            x = 0
            while x <= w {
                let normalX = x / w
                let envelope = sin(normalX * PI)
                let y = sin(normalX * freq * TWO_PI + phase) * amp * envelope
                ctx.vertex(x, yOffset + y)
                x += step
            }
            ctx.endShape()
        }

        // Vertical scanning line
        let scanX = (t * 80).truncatingRemainder(dividingBy: w)
        ctx.colorMode(.rgb, 255)
        ctx.stroke(255, 255, 255, 60)
        ctx.strokeWeight(1)
        ctx.line(scanX, 0, scanX, h)

        // Dots at intersections
        for wave in 0..<waveCount {
            let waveF = Float(wave)
            let yOffset = cy + (waveF - Float(waveCount) / 2) * 120
            let freq = 2 + waveF * 0.7
            let phase = t * (1.5 + waveF * 0.4)
            let amp = 80 - waveF * 8
            let normalX = scanX / w
            let envelope = sin(normalX * PI)
            let y = sin(normalX * freq * TWO_PI + phase) * amp * envelope

            let hue = (waveF * 60 + t * 20).truncatingRemainder(dividingBy: 360)
            ctx.colorMode(.hsb, 360, 255, 255, 255)
            ctx.noStroke()
            ctx.fill(hue, 150, 255, 240)
            ctx.circle(scanX, yOffset + y, 6)
        }
    }
}
