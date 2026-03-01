import metaphor

/// Feature 4 デモ: 動画エクスポート
///
/// スペースキーで録画開始/停止。デスクトップにMP4が保存される。
/// 美しいジェネラティブアニメーションを録画できる。
@main
final class VideoRecord: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Video Record — Press SPACE to record")
    }

    var isRecording = false
    var recordStartTime: Float = 0

    func keyPressed() {
        // スペースキー (keyCode 49) で録画トグル
        guard keyCode == 49 else { return }

        if !isRecording {
            beginVideoRecord()
            isRecording = true
            recordStartTime = time
            print("Recording started...")
        } else {
            endVideoRecord {
                print("Recording saved to Desktop!")
            }
            isRecording = false
        }
    }

    func draw() {
        background(Color(r: 0.02, g: 0.02, b: 0.05))

        let t = time

        // ── ジェネラティブアニメーション ──
        drawSpiral(t: t)
        drawOrbitingParticles(t: t)
        drawPulsingRings(t: t)

        // ── 録画インジケーター ──
        noStroke()
        if isRecording {
            let blink = sin(t * 5) > 0
            if blink {
                fill(Color(r: 1, g: 0.1, b: 0.1))
                circle(width - 50, 50, 20)
            }
            fill(Color(r: 1, g: 0.3, b: 0.3))
            textSize(16)
            textFont("Menlo")
            textAlign(.right, .top)
            let elapsed = t - recordStartTime
            let sec = Int(elapsed)
            text("REC \(sec)s", width - 70, 40)
        } else {
            fill(Color(gray: 0.4))
            textSize(14)
            textFont("Menlo")
            textAlign(.center, .bottom)
            text("Press SPACE to start/stop recording", width / 2, height - 30)
        }
    }

    // MARK: - スパイラル

    private func drawSpiral(t: Float) {
        let cx = width / 2
        let cy = height / 2

        noFill()
        strokeWeight(2)

        for i in 0..<200 {
            let fi = Float(i)
            let angle = fi * 0.15 + t * 0.8
            let r = fi * 2.5
            let x = cx + cos(angle) * r
            let y = cy + sin(angle) * r

            let hue = fmod(fi / 200 + t * 0.1, 1.0)
            let alpha: Float = 1.0 - fi / 200
            colorMode(.hsb, 1)
            stroke(hue, 0.8, 1.0, alpha)
            colorMode(.rgb, 255)

            let sz: Float = 3 + sin(t * 3 + fi * 0.1) * 2
            circle(x, y, sz)
        }
    }

    // MARK: - 軌道パーティクル

    private func drawOrbitingParticles(t: Float) {
        let cx = width / 2
        let cy = height / 2

        noStroke()

        for ring in 0..<3 {
            let ringR: Float = 250 + Float(ring) * 100
            let particleCount = 12 + ring * 6
            let speed: Float = (0.3 + Float(ring) * 0.15) * (ring % 2 == 0 ? 1 : -1)

            for i in 0..<particleCount {
                let angle = Float(i) / Float(particleCount) * Float.pi * 2 + t * speed
                let wobble = sin(t * 2 + Float(i) * 0.5) * 15
                let x = cx + cos(angle) * (ringR + wobble)
                let y = cy + sin(angle) * (ringR + wobble)

                let size: Float = 4 + sin(t * 3 + Float(i)) * 3
                let brightness = 0.5 + sin(t * 2 + Float(i) * 0.8) * 0.5

                switch ring {
                case 0:
                    fill(Color(r: brightness, g: 0.4 * brightness, b: 0.8, a: 0.8))
                case 1:
                    fill(Color(r: 0.3 * brightness, g: brightness, b: 0.6 * brightness, a: 0.7))
                default:
                    fill(Color(r: brightness, g: 0.7 * brightness, b: 0.2 * brightness, a: 0.6))
                }

                circle(x, y, size)
            }
        }
    }

    // MARK: - パルスリング

    private func drawPulsingRings(t: Float) {
        let cx = width / 2
        let cy = height / 2

        noFill()
        strokeWeight(1.5)

        for i in 0..<5 {
            let phase = Float(i) / 5 * Float.pi * 2
            let r = 100 + sin(t * 1.5 + phase) * 80 + Float(i) * 40
            let alpha: Float = 0.3 + sin(t * 2 + phase) * 0.2
            stroke(Color(r: 0.5, g: 0.7, b: 1.0, a: alpha))
            circle(cx, cy, r * 2)
        }
    }
}
