import metaphor

@main
final class SineAndCosineExample: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Sine and Cosine")
    }

    func draw() {
        background(Color(gray: 0.08))

        let circleX: Float = 300
        let circleY = height / 2
        let radius: Float = 200
        let waveStartX: Float = 560
        let waveEndX = width - 60
        let waveLen = waveEndX - waveStartX

        let phase = time * 1.5
        let px = circleX + cos(phase) * radius
        let py = circleY + sin(phase) * radius

        // 軸線
        stroke(Color(gray: 0.25))
        strokeWeight(1)
        line(circleX - radius - 20, circleY, circleX + radius + 20, circleY)
        line(circleX, circleY - radius - 20, circleX, circleY + radius + 20)

        // 円
        noFill()
        stroke(Color(gray: 0.4))
        strokeWeight(2)
        circle(circleX, circleY, radius * 2)

        // 半径線
        stroke(Color(gray: 0.7))
        line(circleX, circleY, px, py)

        // sin成分（赤・垂直線）
        stroke(Color(r: 1, g: 0.3, b: 0.3, a: 0.9))
        strokeWeight(2)
        line(px, circleY, px, py)

        // cos成分（青・水平線）
        stroke(Color(r: 0.3, g: 0.5, b: 1.0, a: 0.9))
        line(circleX, py, px, py)

        // 円上の点
        fill(.white)
        noStroke()
        circle(px, py, 14)

        // 接続線
        stroke(Color(r: 1, g: 0.3, b: 0.3, a: 0.3))
        strokeWeight(1)
        line(px, py, waveStartX, py)

        // 波中心線
        stroke(Color(gray: 0.2))
        line(waveStartX, circleY, waveEndX, circleY)

        // sin波（赤）
        stroke(Color(r: 1, g: 0.3, b: 0.3, a: 0.9))
        strokeWeight(2)
        let n = 300
        for i in 0..<n {
            let t0 = Float(i) / Float(n)
            let t1 = Float(i + 1) / Float(n)
            let x0 = waveStartX + t0 * waveLen
            let x1 = waveStartX + t1 * waveLen
            line(x0, circleY + sin(phase + t0 * 4 * Float.pi) * radius,
                 x1, circleY + sin(phase + t1 * 4 * Float.pi) * radius)
        }

        // cos波（青）
        stroke(Color(r: 0.3, g: 0.5, b: 1.0, a: 0.9))
        for i in 0..<n {
            let t0 = Float(i) / Float(n)
            let t1 = Float(i + 1) / Float(n)
            let x0 = waveStartX + t0 * waveLen
            let x1 = waveStartX + t1 * waveLen
            line(x0, circleY + cos(phase + t0 * 4 * Float.pi) * radius,
                 x1, circleY + cos(phase + t1 * 4 * Float.pi) * radius)
        }

        // 開始点
        noStroke()
        fill(Color(r: 1, g: 0.3, b: 0.3))
        circle(waveStartX, circleY + sin(phase) * radius, 10)
        fill(Color(r: 0.3, g: 0.5, b: 1.0))
        circle(waveStartX, circleY + cos(phase) * radius, 10)
    }
}
