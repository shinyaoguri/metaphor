import metaphor

struct BVec {
    var x: Float
    var y: Float
}

struct BezierCurve {
    let segmentCount = 100
    var v0, v1, v2, v3: BVec
    var arcLengths: [Float]
    var curveLength: Float

    init(a: BVec, b: BVec, c: BVec, d: BVec) {
        v0 = a; v1 = b; v2 = c; v3 = d
        arcLengths = [Float](repeating: 0, count: 101)
        curveLength = 0

        var arcLen: Float = 0
        var prev = v0
        for i in 0...segmentCount {
            let t = Float(i) / Float(segmentCount)
            let pt = BezierCurve.bezPoint(v0, v1, v2, v3, t)
            let dx = pt.x - prev.x
            let dy = pt.y - prev.y
            arcLen += sqrt(dx * dx + dy * dy)
            arcLengths[i] = arcLen
            prev = pt
        }
        curveLength = arcLen
    }

    static func bezPoint(_ p0: BVec, _ p1: BVec, _ p2: BVec, _ p3: BVec, _ t: Float) -> BVec {
        let u = 1 - t
        let tt = t * t
        let uu = u * u
        let uuu = uu * u
        let ttt = tt * t
        let x = uuu * p0.x + 3 * uu * t * p1.x + 3 * u * tt * p2.x + ttt * p3.x
        let y = uuu * p0.y + 3 * uu * t * p1.y + 3 * u * tt * p2.y + ttt * p3.y
        return BVec(x: x, y: y)
    }

    func pointAtParameter(_ t: Float) -> BVec {
        BezierCurve.bezPoint(v0, v1, v2, v3, t)
    }

    func pointAtFraction(_ r: Float) -> BVec {
        pointAtLength(curveLength * r)
    }

    func pointAtLength(_ wanted: Float) -> BVec {
        let w = min(max(wanted, 0), curveLength)
        // binary search
        var lo = 0, hi = segmentCount
        while lo < hi {
            let mid = (lo + hi) / 2
            if arcLengths[mid] < w { lo = mid + 1 } else { hi = mid }
        }
        let nextIdx = lo
        if nextIdx == 0 { return pointAtParameter(0) }
        let prevIdx = nextIdx - 1
        let prevLen = arcLengths[prevIdx]
        let nextLen = arcLengths[nextIdx]
        let frac = (nextLen > prevLen) ? (w - prevLen) / (nextLen - prevLen) : 0
        let mappedIdx = Float(prevIdx) + frac
        let parameter = mappedIdx / Float(segmentCount)
        return pointAtParameter(parameter)
    }

    func points(_ count: Int) -> [BVec] {
        var result = [BVec](repeating: BVec(x: 0, y: 0), count: count)
        result[0] = v0
        result[count - 1] = v3
        for i in 1..<(count - 1) {
            let param = Float(i) / Float(count - 1)
            result[i] = pointAtParameter(param)
        }
        return result
    }

    func equidistantPoints(_ count: Int) -> [BVec] {
        var result = [BVec](repeating: BVec(x: 0, y: 0), count: count)
        result[0] = v0
        result[count - 1] = v3
        var arcIdx = 1
        for i in 1..<(count - 1) {
            let fraction = Float(i) / Float(count - 1)
            let wantedLen = fraction * curveLength
            while arcIdx < arcLengths.count && arcLengths[arcIdx] < wantedLen {
                arcIdx += 1
            }
            let nextIdx = min(arcIdx, segmentCount)
            let prevIdx = nextIdx - 1
            let prevLen = arcLengths[prevIdx]
            let nextLen = arcLengths[nextIdx]
            let frac = (nextLen > prevLen) ? (wantedLen - prevLen) / (nextLen - prevLen) : 0
            let mappedIdx = Float(prevIdx) + frac
            let parameter = mappedIdx / Float(segmentCount)
            result[i] = pointAtParameter(parameter)
        }
        return result
    }
}

@main
final class ArcLengthParametrization: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "ArcLengthParametrization", width: 640, height: 360)
    }

    var curve: BezierCurve!
    var pts: [BVec] = []
    var eqPts: [BVec] = []
    var t: Float = 0
    let tStep: Float = 0.004
    let pointCount = 80
    let borderSize: Float = 40

    func setup() {
        textAlign(.center)
        textSize(16)
        strokeWeight(2)

        let a = BVec(x: 0, y: 300)
        let b = BVec(x: 440, y: 0)
        let c = BVec(x: -200, y: 0)
        let d = BVec(x: 240, y: 300)

        curve = BezierCurve(a: a, b: b, c: c, d: d)
        pts = curve.points(pointCount)
        eqPts = curve.equidistantPoints(pointCount)
    }

    func draw() {
        if isMousePressed {
            let a = constrain(mouseX, borderSize, width - borderSize)
            t = map(a, borderSize, width - borderSize, 0, 1)
        } else {
            t += tStep
            if t > 1.0 { t = 0 }
        }

        background(255)

        // Standard parametrization
        pushMatrix()
        translate(borderSize, -50)

        noStroke(); fill(120)
        text("STANDARD\nPARAMETRIZATION", 120, 310)

        stroke(170); noFill()
        beginShape(.lines)
        for i in stride(from: 0, to: pts.count - 1, by: 2) {
            vertex(pts[i].x, pts[i].y)
            vertex(pts[i + 1].x, pts[i + 1].y)
        }
        endShape()

        noStroke(); fill(0)
        let pos1 = curve.pointAtParameter(t)
        ellipse(pos1.x, pos1.y, 12, 12)
        popMatrix()

        // Arc length parametrization
        pushMatrix()
        translate(width / 2 + borderSize, -50)

        noStroke(); fill(120)
        text("ARC LENGTH\nPARAMETRIZATION", 120, 310)

        stroke(170); noFill()
        beginShape(.lines)
        for i in stride(from: 0, to: eqPts.count - 1, by: 2) {
            vertex(eqPts[i].x, eqPts[i].y)
            vertex(eqPts[i + 1].x, eqPts[i + 1].y)
        }
        endShape()

        noStroke(); fill(0)
        let pos2 = curve.pointAtFraction(t)
        ellipse(pos2.x, pos2.y, 12, 12)
        popMatrix()

        // Seek bar
        pushMatrix()
        translate(borderSize, height - 45)
        let barLength = width - 2 * borderSize

        stroke(220); noFill()
        line(0, 0, barLength, 0)
        line(barLength, -5, barLength, 5)

        stroke(50); noFill()
        line(0, -5, 0, 5)
        line(0, 0, t * barLength, 0)

        noStroke(); fill(120)
        text(String(format: "%.2f", t), barLength / 2, 25)
        popMatrix()
    }
}
