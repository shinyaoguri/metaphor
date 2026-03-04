import metaphor

struct KochPoint {
    var x: Float
    var y: Float
}

struct KochLine {
    var a: KochPoint
    var b: KochPoint

    func start() -> KochPoint { a }
    func end() -> KochPoint { b }

    func kochLeft() -> KochPoint {
        let dx = (b.x - a.x) / 3
        let dy = (b.y - a.y) / 3
        return KochPoint(x: a.x + dx, y: a.y + dy)
    }

    func kochRight() -> KochPoint {
        let dx = (a.x - b.x) / 3
        let dy = (a.y - b.y) / 3
        return KochPoint(x: b.x + dx, y: b.y + dy)
    }

    func kochMiddle() -> KochPoint {
        let dx = (b.x - a.x) / 3
        let dy = (b.y - a.y) / 3
        let px = a.x + dx
        let py = a.y + dy
        let angle = -Float.pi / 3  // -60 degrees
        let rx = dx * cos(angle) - dy * sin(angle)
        let ry = dx * sin(angle) + dy * cos(angle)
        return KochPoint(x: px + rx, y: py + ry)
    }
}

@main
final class Koch: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 640, height: 360, title: "Koch")
    }

    var lines: [KochLine] = []
    var count = 0

    func setup() {
        frameRate(1)
        restart()
    }

    func restart() {
        count = 0
        lines = [KochLine(a: KochPoint(x: 0, y: height - 20), b: KochPoint(x: width, y: height - 20))]
    }

    func nextLevel() {
        var newLines: [KochLine] = []
        for l in lines {
            let a = l.start()
            let b = l.kochLeft()
            let c = l.kochMiddle()
            let d = l.kochRight()
            let e = l.end()
            newLines.append(KochLine(a: a, b: b))
            newLines.append(KochLine(a: b, b: c))
            newLines.append(KochLine(a: c, b: d))
            newLines.append(KochLine(a: d, b: e))
        }
        lines = newLines
        count += 1
    }

    func draw() {
        background(0)
        stroke(255)
        for l in lines {
            line(l.a.x, l.a.y, l.b.x, l.b.y)
        }
        nextLevel()
        if count > 5 {
            restart()
        }
    }
}
