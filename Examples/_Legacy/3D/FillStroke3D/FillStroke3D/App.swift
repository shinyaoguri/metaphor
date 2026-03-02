import metaphor

/// Feature 2 デモ: fill/stroke 2D/3D 統一 API
///
/// 同じ fill() / stroke() / noFill() / noStroke() が 2D と 3D の両方に反映される。
/// 3D stroke はワイヤーフレーム描画になる。
@main
final class FillStroke3D: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Fill & Stroke — 2D/3D Unified")
    }

    func draw() {
        background(Color(gray: 0.04))

        let t = time

        camera(
            eye: SIMD3<Float>(0, 100, 700),
            center: SIMD3<Float>(0, -20, 0),
            up: SIMD3<Float>(0, 1, 0)
        )
        perspective(fov: radians(50), near: 1, far: 2000)

        // ── 行1: fill のみ（noStroke）──
        drawFillOnlyRow(y: 200, t: t)

        // ── 行2: stroke のみ（noFill）= ワイヤーフレーム ──
        drawWireframeRow(y: 0, t: t)

        // ── 行3: fill + stroke 重ね描き ──
        drawFillAndStrokeRow(y: -200, t: t)

        // ── UI ──
        noLights()
        fill(Color(gray: 0.45))
        noStroke()
        textSize(14)
        textFont("Menlo")
        textAlign(.left, .top)
        text("Row 1: fill only", 30, 30)
        text("Row 2: wireframe (noFill + stroke)", 30, 50)
        text("Row 3: fill + stroke overlay", 30, 70)
    }

    // MARK: - Row 1: fill のみ

    private func drawFillOnlyRow(y: Float, t: Float) {
        noStroke()

        noLights()
        directionalLight(0.5, -1, -0.7)
        ambientLight(0.15)

        // HSBカラーモードで虹色に変化
        colorMode(.hsb, 1)

        let shapes = 5
        let spacing: Float = 250

        for i in 0..<shapes {
            let hue = fmod(Float(i) / Float(shapes) + t * 0.05, 1.0)

            pushMatrix()
            translate(Float(i - shapes / 2) * spacing, y, 0)
            rotateY(t * 0.5 + Float(i) * 0.3)
            rotateX(t * 0.3)

            fill(hue, 0.7, 0.95)

            switch i % 5 {
            case 0: sphere(55, detail: 32)
            case 1: box(90)
            case 2: cylinder(radius: 40, height: 100, detail: 24)
            case 3: cone(radius: 50, height: 100, detail: 24)
            default: torus(ringRadius: 50, tubeRadius: 18, detail: 24)
            }

            popMatrix()
        }

        colorMode(.rgb, 255)
    }

    // MARK: - Row 2: ワイヤーフレーム

    private func drawWireframeRow(y: Float, t: Float) {
        noFill()

        noLights()

        let shapes = 5
        let spacing: Float = 250

        for i in 0..<shapes {
            let phase = Float(i) / Float(shapes) * Float.pi * 2
            let pulse = (sin(t * 2 + phase) + 1) * 0.5

            stroke(Color(r: 0.3 + pulse * 0.7, g: 0.8, b: 1.0 - pulse * 0.5))

            pushMatrix()
            translate(Float(i - shapes / 2) * spacing, y, 0)
            rotateY(t * 0.7 + Float(i) * 0.5)
            rotateX(t * 0.4)

            switch i % 5 {
            case 0: sphere(55, detail: 16)
            case 1: box(90)
            case 2: cylinder(radius: 40, height: 100, detail: 12)
            case 3: cone(radius: 50, height: 100, detail: 12)
            default: torus(ringRadius: 50, tubeRadius: 18, detail: 12)
            }

            popMatrix()
        }
    }

    // MARK: - Row 3: fill + stroke

    private func drawFillAndStrokeRow(y: Float, t: Float) {
        noLights()
        directionalLight(0.4, -1, -0.6)
        ambientLight(0.1)

        let shapes = 5
        let spacing: Float = 250

        for i in 0..<shapes {
            pushMatrix()
            translate(Float(i - shapes / 2) * spacing, y, 0)
            rotateY(t * 0.4 + Float(i) * 0.6)
            rotateX(t * 0.25)

            // 暗めのfill + 明るいstroke
            fill(Color(r: 0.15, g: 0.1, b: 0.2))
            stroke(Color(r: 1.0, g: 0.4, b: 0.6))

            switch i % 5 {
            case 0: sphere(55, detail: 16)
            case 1: box(90)
            case 2: cylinder(radius: 40, height: 100, detail: 12)
            case 3: cone(radius: 50, height: 100, detail: 12)
            default: torus(ringRadius: 50, tubeRadius: 18, detail: 12)
            }

            popMatrix()
        }

        noStroke()
    }
}
