import metaphor

/// Syphon Multi-Window Demo
///
/// Two FHD windows, each publishing to a separate Syphon server:
/// - "metaphor - Main"  : Rotating 3D geometry with lighting
/// - "metaphor - Sub"   : 2D particle trails reacting to main window state
///
/// Open a Syphon client to receive either or both textures independently.
@main
final class SyphonMultiWindow: Sketch {
    var config: SketchConfig {
        SketchConfig(
            width: 1920,
            height: 1080,
            title: "Syphon Main",
            fps: 60,
            syphonName: "metaphor - Main",
            windowScale: 0.4
        )
    }

    var sub: SketchWindow?

    // Particle state for sub window
    let particleCount = 200
    var px: [Float] = []
    var py: [Float] = []
    var vx: [Float] = []
    var vy: [Float] = []

    func setup() {
        sub = createWindow(SketchWindowConfig(
            width: 1920,
            height: 1080,
            title: "Syphon Sub",
            fps: 60,
            windowScale: 0.4,
            syphonName: "metaphor - Sub"
        ))

        // Initialize particles at center
        for _ in 0..<particleCount {
            px.append(960)
            py.append(540)
            vx.append(Float.random(in: -2...2))
            vy.append(Float.random(in: -2...2))
        }
    }

    func draw() {
        let t = Float(frameCount) * 0.01

        // === Main window: 3D scene ===
        background(15, 15, 25)
        lights()

        translate(width / 2, height / 2, 0)
        rotateX(sin(t * 0.7) * 0.3)
        rotateY(t * 0.5)

        // Central sphere
        fill(80, 160, 255)
        noStroke()
        sphere(120)

        // Orbiting boxes
        let orbitCount = 8
        for i in 0..<orbitCount {
            let angle = Float(i) / Float(orbitCount) * TWO_PI + t
            let orbitR: Float = 300
            let yOff = sin(t * 2 + Float(i)) * 80

            pushMatrix()
            translate(cos(angle) * orbitR, yOff, sin(angle) * orbitR)
            rotateX(t * 1.5)
            rotateZ(t * 0.8)

            let r = 100 + sin(t + Float(i) * 0.8) * 155
            let g = 150 + cos(t * 0.7 + Float(i)) * 105
            let b: Float = 255
            fill(r, g, b)
            box(40 + sin(t + Float(i)) * 15)
            popMatrix()
        }

        // Outer ring of small spheres
        noLights()
        let ringCount = 24
        for i in 0..<ringCount {
            let angle = Float(i) / Float(ringCount) * TWO_PI - t * 0.3
            let rr: Float = 500
            pushMatrix()
            translate(cos(angle) * rr, sin(angle * 3 + t) * 40, sin(angle) * rr)
            let bright = 150 + sin(t * 3 + Float(i)) * 105
            fill(bright, bright, 255, 200)
            sphere(8)
            popMatrix()
        }

        // === Sub window: 2D particle trails ===
        let capturedT = t
        let capturedPx = px
        let capturedPy = py
        sub?.draw { [self] ctx in
            ctx.background(10, 8, 20, 20)

            // Update particles
            let cx: Float = 960
            let cy: Float = 540
            for i in 0..<particleCount {
                // Attract toward center with swirl
                let dx = cx - px[i]
                let dy = cy - py[i]
                let dist = sqrt(dx * dx + dy * dy) + 1
                let force: Float = 0.3

                vx[i] += (dx / dist * force) + cos(capturedT * 2 + Float(i)) * 0.5
                vy[i] += (dy / dist * force) + sin(capturedT * 2 + Float(i)) * 0.5

                // Damping
                vx[i] *= 0.98
                vy[i] *= 0.98

                px[i] += vx[i]
                py[i] += vy[i]

                // Wrap around
                if px[i] < 0 { px[i] += 1920 }
                if px[i] > 1920 { px[i] -= 1920 }
                if py[i] < 0 { py[i] += 1080 }
                if py[i] > 1080 { py[i] -= 1080 }

                // Draw particle
                let speed = sqrt(vx[i] * vx[i] + vy[i] * vy[i])
                let hue = (Float(i) / Float(particleCount) * 360 + capturedT * 20)
                    .truncatingRemainder(dividingBy: 360)
                let alpha = min(speed * 30, 255)
                let size = 3 + speed * 2

                ctx.colorMode(.hsb, 360, 255, 255, 255)
                ctx.noStroke()
                ctx.fill(hue, 200, 255, alpha)
                ctx.circle(px[i], py[i], size)
            }

            // Connection lines between nearby particles
            ctx.colorMode(.rgb, 255)
            for i in stride(from: 0, to: particleCount, by: 2) {
                for j in stride(from: i + 1, to: min(i + 10, particleCount), by: 1) {
                    let dx = capturedPx[i] - capturedPx[j]
                    let dy = capturedPy[i] - capturedPy[j]
                    let dist = sqrt(dx * dx + dy * dy)
                    if dist < 80 {
                        let alpha = (1 - dist / 80) * 60
                        ctx.stroke(120, 180, 255, alpha)
                        ctx.strokeWeight(0.5)
                        ctx.line(capturedPx[i], capturedPy[i], capturedPx[j], capturedPy[j])
                    }
                }
            }

            // Title overlay
            ctx.colorMode(.rgb, 255)
            ctx.fill(255, 255, 255, 180)
            ctx.noStroke()
            ctx.textSize(14)
            ctx.textAlign(.left, .top)
            ctx.text("Syphon: metaphor - Sub", 20, 20)
        }
    }
}
