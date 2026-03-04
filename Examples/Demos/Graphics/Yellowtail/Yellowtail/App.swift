import metaphor

// Vec3f - point with pressure
struct GesturePoint {
    var x: Float = 0
    var y: Float = 0
    var p: Float = 0  // pressure
}

// Quad polygon (4 vertices)
struct QuadPoly {
    var x: [Int] = [0, 0, 0, 0]
    var y: [Int] = [0, 0, 0, 0]
}

class Gesture {
    let damp: Float = 5.0
    var dampInv: Float { 1.0 / damp }
    var damp1: Float { damp - 1 }

    let w: Int
    let h: Int
    let capacity = 600

    var path: [GesturePoint]
    var crosses: [Int]
    var polygons: [QuadPoly]
    var nPoints = 0
    var nPolys = 0

    var jumpDx: Float = 0
    var jumpDy: Float = 0
    var exists = false
    let INIT_TH: Float = 14
    var thickness: Float = 14

    init(_ mw: Int, _ mh: Int) {
        w = mw; h = mh
        path = Array(repeating: GesturePoint(), count: capacity)
        polygons = Array(repeating: QuadPoly(), count: capacity)
        crosses = Array(repeating: 0, count: capacity)
    }

    func clear() {
        nPoints = 0; exists = false; thickness = INIT_TH
    }
    func clearPolys() { nPolys = 0 }

    func distToLast(_ ix: Float, _ iy: Float) -> Float {
        if nPoints > 0 {
            let v = path[nPoints - 1]
            let dx = v.x - ix, dy = v.y - iy
            return sqrt(dx * dx + dy * dy)
        }
        return 30
    }

    func getPressureFromVelocity(_ v: Float) -> Float {
        let scale: Float = 18
        let minP: Float = 0.02
        let oldP = nPoints > 0 ? path[nPoints - 1].p : Float(0)
        return ((minP + max(0, 1.0 - v / scale)) + (damp1 * oldP)) * dampInv
    }

    func addPoint(_ x: Float, _ y: Float) {
        if nPoints >= capacity { return }
        let v = distToLast(x, y)
        let p = getPressureFromVelocity(v)
        path[nPoints] = GesturePoint(x: x, y: y, p: p)
        nPoints += 1
        if nPoints > 1 {
            exists = true
            jumpDx = path[nPoints - 1].x - path[0].x
            jumpDy = path[nPoints - 1].y - path[0].y
        }
    }

    func smooth() {
        let weight: Float = 18
        let scale: Float = 1.0 / (weight + 2)
        for i in 1..<(nPoints - 2) {
            let lower = path[i - 1]
            path[i].x = (lower.x + weight * path[i].x + path[i + 1].x) * scale
            path[i].y = (lower.y + weight * path[i].y + path[i + 1].y) * scale
        }
    }

    func compile() {
        guard exists else { return }
        clearPolys()

        let nPathPoints = nPoints - 1
        guard nPathPoints > 0 else { return }
        let lastPolyIndex = nPathPoints - 1
        let npm1finv: Float = 1.0 / max(1, Float(nPathPoints - 1))

        let p0 = path[0], p1 = path[1]
        var radius0 = p0.p * thickness
        var dx01 = p1.x - p0.x, dy01 = p1.y - p0.y
        var hp01 = sqrt(dx01 * dx01 + dy01 * dy01)
        if hp01 == 0 { hp01 = 0.0001 }
        let co01 = radius0 * dx01 / hp01
        let si01 = radius0 * dy01 / hp01
        var ax = p0.x - si01, ay = p0.y + co01
        var bx = p0.x + si01, by = p0.y - co01

        let LC = 20, RC = w - LC, TC = 20, BC = h - TC
        let mint: Float = 0.618, tapow: Float = 0.4

        for i in 1..<nPathPoints {
            let taper = pow(Float(lastPolyIndex - i) * npm1finv, tapow)
            let pp0 = path[i - 1], pp1 = path[i], pp2 = path[i + 1]
            let radius1 = max(mint, taper * pp1.p * thickness)

            var dx02 = pp2.x - pp0.x, dy02 = pp2.y - pp0.y
            var hp02 = sqrt(dx02 * dx02 + dy02 * dy02)
            if hp02 != 0 { hp02 = radius1 / hp02 }
            let co02 = dx02 * hp02, si02 = dy02 * hp02

            var axi = Int(ax), ayi = Int(ay)
            let axip = axi, ayip = ayi
            axi = axi < 0 ? (w - ((-axi) % w)) : axi % w
            let axid = axi - axip
            ayi = ayi < 0 ? (h - ((-ayi) % h)) : ayi % h
            let ayid = ayi - ayip

            let cx = pp1.x + si02, cy = pp1.y - co02
            let dx = pp1.x - si02, dy = pp1.y + co02

            var poly = QuadPoly()
            poly.x[0] = axid + axip; poly.x[1] = axid + Int(bx)
            poly.x[2] = axid + Int(cx); poly.x[3] = axid + Int(dx)
            poly.y[0] = ayid + ayip; poly.y[1] = ayid + Int(by)
            poly.y[2] = ayid + Int(cy); poly.y[3] = ayid + Int(dy)

            crosses[nPolys] = 0
            if poly.x[0] <= LC || poly.x[1] <= LC || poly.x[2] <= LC || poly.x[3] <= LC { crosses[nPolys] |= 1 }
            if poly.x[0] >= RC || poly.x[1] >= RC || poly.x[2] >= RC || poly.x[3] >= RC { crosses[nPolys] |= 2 }
            if poly.y[0] <= TC || poly.y[1] <= TC || poly.y[2] <= TC || poly.y[3] <= TC { crosses[nPolys] |= 4 }
            if poly.y[0] >= BC || poly.y[1] >= BC || poly.y[2] >= BC || poly.y[3] >= BC { crosses[nPolys] |= 8 }

            polygons[nPolys] = poly
            nPolys += 1

            ax = dx; ay = dy; bx = cx; by = cy
        }

        // Last point
        let pLast = path[nPathPoints]
        var lastPoly = QuadPoly()
        lastPoly.x[0] = Int(ax); lastPoly.x[1] = Int(bx)
        lastPoly.x[2] = Int(pLast.x); lastPoly.x[3] = Int(pLast.x)
        lastPoly.y[0] = Int(ay); lastPoly.y[1] = Int(by)
        lastPoly.y[2] = Int(pLast.y); lastPoly.y[3] = Int(pLast.y)
        polygons[nPolys] = lastPoly
        nPolys += 1
    }
}

@main
final class Yellowtail: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 1024, height: 768, title: "Yellowtail")
    }

    let nGestures = 36
    let minMove: Float = 3
    var currentGestureID = -1
    var gestureArray: [Gesture] = []

    func setup() {
        background(0)
        noStroke()
        for _ in 0..<nGestures {
            gestureArray.append(Gesture(Int(width), Int(height)))
        }
    }

    func draw() {
        background(0)
        updateGeometry()
        fill(255, 255, 245)
        noStroke()
        for i in 0..<nGestures {
            renderGesture(gestureArray[i])
        }
    }

    func mousePressed() {
        currentGestureID = (currentGestureID + 1) % nGestures
        let g = gestureArray[currentGestureID]
        g.clear()
        g.clearPolys()
        g.addPoint(mouseX, mouseY)
    }

    func mouseDragged() {
        if currentGestureID >= 0 {
            let g = gestureArray[currentGestureID]
            if g.distToLast(mouseX, mouseY) > minMove {
                g.addPoint(mouseX, mouseY)
                g.smooth()
                g.compile()
            }
        }
    }

    func keyPressed() {
        if key == "+" || key == "=" {
            if currentGestureID >= 0 {
                gestureArray[currentGestureID].thickness = min(96, gestureArray[currentGestureID].thickness + 1)
                gestureArray[currentGestureID].compile()
            }
        } else if key == "-" {
            if currentGestureID >= 0 {
                gestureArray[currentGestureID].thickness = max(2, gestureArray[currentGestureID].thickness - 1)
                gestureArray[currentGestureID].compile()
            }
        } else if key == " " {
            for g in gestureArray { g.clear() }
        }
    }

    func renderGesture(_ gesture: Gesture) {
        guard gesture.exists, gesture.nPolys > 0 else { return }
        let w = Int(width), h = Int(height)

        beginShape(.triangles)
        for i in 0..<gesture.nPolys {
            let p = gesture.polygons[i]
            // Quad as 2 triangles
            vertex(Float(p.x[0]), Float(p.y[0]))
            vertex(Float(p.x[1]), Float(p.y[1]))
            vertex(Float(p.x[2]), Float(p.y[2]))
            vertex(Float(p.x[0]), Float(p.y[0]))
            vertex(Float(p.x[2]), Float(p.y[2]))
            vertex(Float(p.x[3]), Float(p.y[3]))

            let cr = gesture.crosses[i]
            if cr > 0 {
                if (cr & 3) > 0 {
                    // Wrap horizontally
                    vertex(Float(p.x[0] + w), Float(p.y[0]))
                    vertex(Float(p.x[1] + w), Float(p.y[1]))
                    vertex(Float(p.x[2] + w), Float(p.y[2]))
                    vertex(Float(p.x[0] + w), Float(p.y[0]))
                    vertex(Float(p.x[2] + w), Float(p.y[2]))
                    vertex(Float(p.x[3] + w), Float(p.y[3]))

                    vertex(Float(p.x[0] - w), Float(p.y[0]))
                    vertex(Float(p.x[1] - w), Float(p.y[1]))
                    vertex(Float(p.x[2] - w), Float(p.y[2]))
                    vertex(Float(p.x[0] - w), Float(p.y[0]))
                    vertex(Float(p.x[2] - w), Float(p.y[2]))
                    vertex(Float(p.x[3] - w), Float(p.y[3]))
                }
                if (cr & 12) > 0 {
                    vertex(Float(p.x[0]), Float(p.y[0] + h))
                    vertex(Float(p.x[1]), Float(p.y[1] + h))
                    vertex(Float(p.x[2]), Float(p.y[2] + h))
                    vertex(Float(p.x[0]), Float(p.y[0] + h))
                    vertex(Float(p.x[2]), Float(p.y[2] + h))
                    vertex(Float(p.x[3]), Float(p.y[3] + h))

                    vertex(Float(p.x[0]), Float(p.y[0] - h))
                    vertex(Float(p.x[1]), Float(p.y[1] - h))
                    vertex(Float(p.x[2]), Float(p.y[2] - h))
                    vertex(Float(p.x[0]), Float(p.y[0] - h))
                    vertex(Float(p.x[2]), Float(p.y[2] - h))
                    vertex(Float(p.x[3]), Float(p.y[3] - h))
                }
            }
        }
        endShape()
    }

    func updateGeometry() {
        for g in 0..<nGestures {
            if gestureArray[g].exists {
                if g != currentGestureID {
                    advanceGesture(gestureArray[g])
                } else if !isMousePressed {
                    advanceGesture(gestureArray[g])
                }
            }
        }
    }

    func advanceGesture(_ gesture: Gesture) {
        guard gesture.exists else { return }
        let nPts = gesture.nPoints
        let nPts1 = nPts - 1
        guard nPts > 0 else { return }

        for i in stride(from: nPts1, through: 1, by: -1) {
            gesture.path[i].x = gesture.path[i - 1].x
            gesture.path[i].y = gesture.path[i - 1].y
        }
        gesture.path[0].x = gesture.path[nPts1].x - gesture.jumpDx
        gesture.path[0].y = gesture.path[nPts1].y - gesture.jumpDy
        gesture.compile()
    }
}
