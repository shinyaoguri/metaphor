import metaphor

@main
final class ProbeStateSketch: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "ProbeState")
    }

    /// 3 つの点。軌道の大きさと速さだけが違う
    let orbits: [(radiusX: Float, radiusY: Float, speed: Float, offset: Float)] = [
        (170, 110, 0.9, 0),
        (120, 140, -1.4, 1.7),
        (210, 70, 0.55, 3.4),
    ]
    let names = ["A", "B", "C"]

    /// この距離より近ければ「触れている」とみなす
    let touchDistance: Float = 90

    func draw() {
        background(12, 14, 20)

        // 位置はフレーム番号だけで決まる。同じフレームなら何度でも同じ絵になる
        let positions = orbits.map { position(for: $0) }
        let (pair, distance) = closestPair(positions)

        drawConnections(positions, closest: pair)
        drawDots(positions, closest: pair, distance: distance)

        // 絵から読めるのは「近そうかどうか」まで。値そのものは申告しないと伝わらない。
        // プラグインが登録されていないとき、この呼び出しは完全な no-op
        probe("dots.count", positions.count)
        probe("closest.pair", "\(names[pair.0])-\(names[pair.1])")
        probe("closest.distance", Double(distance))
        probe("closest.midpoint", (positions[pair.0] + positions[pair.1]) * 0.5)
        probe("isTouching", distance < touchDistance)
    }

    private func position(for orbit: (radiusX: Float, radiusY: Float, speed: Float, offset: Float)) -> Vec2 {
        let angle = Float(frameCount) * 0.01 * orbit.speed + orbit.offset
        return Vec2(
            width / 2 + cos(angle) * orbit.radiusX,
            height / 2 + sin(angle) * orbit.radiusY
        )
    }

    /// いちばん近い 2 点と、その距離
    private func closestPair(_ positions: [Vec2]) -> (pair: (Int, Int), distance: Float) {
        var best = (pair: (0, 1), distance: Float.greatestFiniteMagnitude)
        for i in 0..<positions.count {
            for j in (i + 1)..<positions.count {
                let d = positions[i].dist(to: positions[j])
                if d < best.distance {
                    best = (pair: (i, j), distance: d)
                }
            }
        }
        return best
    }

    private func drawConnections(_ positions: [Vec2], closest: (Int, Int)) {
        for i in 0..<positions.count {
            for j in (i + 1)..<positions.count {
                let isClosest = (i, j) == closest
                stroke(isClosest ? Color(r: 1, g: 0.75, b: 0.3) : Color(gray: 0.28))
                strokeWeight(isClosest ? 2 : 1)
                line(positions[i].x, positions[i].y, positions[j].x, positions[j].y)
            }
        }
    }

    private func drawDots(_ positions: [Vec2], closest: (Int, Int), distance: Float) {
        noStroke()
        for (index, p) in positions.enumerated() {
            let isClosest = index == closest.0 || index == closest.1
            fill(isClosest ? Color(r: 1, g: 0.75, b: 0.3) : Color(r: 0.45, g: 0.7, b: 1))
            circle(p.x, p.y, 26)

            fill(12, 14, 20)
            textSize(13)
            textAlign(.center, .center)
            text(names[index], p.x, p.y)
        }

        fill(210)
        textSize(13)
        textAlign(.left, .baseline)
        let state = distance < touchDistance ? "触れている" : "離れている"
        text("closest \(names[closest.0])-\(names[closest.1])  \(Int(distance))px  \(state)", 16, height - 18)
    }
}
