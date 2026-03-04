import metaphor

@main
final class TextureSphere: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "TextureSphere", width: 640, height: 360)
    }

    var ptsW = 30
    var ptsH = 30
    var img: MImage!

    var coorX: [Float] = []
    var coorY: [Float] = []
    var coorZ: [Float] = []
    var multXZ: [Float] = []
    var numPointsW = 0
    var numPointsH = 0
    var numPointsH2pi = 0

    func setup() {
        noStroke()
        let sz = 128
        img = createImage(sz, sz)
        img.loadPixels()
        for y in 0..<sz {
            for x in 0..<sz {
                let idx = (y * sz + x) * 4
                // Earth-like color: blue ocean + green land
                let nx = Float(x) / Float(sz)
                let ny = Float(y) / Float(sz)
                if sin(nx * 10) * cos(ny * 8) > 0.3 {
                    img.pixels[idx] = 60; img.pixels[idx + 1] = 150; img.pixels[idx + 2] = 60
                } else {
                    img.pixels[idx] = 30; img.pixels[idx + 1] = 80; img.pixels[idx + 2] = 180
                }
                img.pixels[idx + 3] = 255
            }
        }
        img.updatePixels()
        initSphere(ptsW, ptsH)
    }

    func initSphere(_ numPtsW: Int, _ numPtsH2pi: Int) {
        self.numPointsW = numPtsW + 1
        self.numPointsH2pi = numPtsH2pi
        self.numPointsH = Int(ceil(Float(numPtsH2pi) / 2.0)) + 1

        coorX = [Float](repeating: 0, count: numPointsW)
        coorY = [Float](repeating: 0, count: numPointsH)
        coorZ = [Float](repeating: 0, count: numPointsW)
        multXZ = [Float](repeating: 0, count: numPointsH)

        for i in 0..<numPointsW {
            let thetaW = Float(i) * 2 * .pi / Float(numPointsW - 1)
            coorX[i] = sin(thetaW)
            coorZ[i] = cos(thetaW)
        }

        for i in 0..<numPointsH {
            if numPointsH2pi % 2 != 0 && i == numPointsH - 1 {
                let thetaH = Float(i - 1) * 2 * .pi / Float(numPointsH2pi)
                coorY[i] = cos(.pi + thetaH)
                multXZ[i] = 0
            } else {
                let thetaH = Float(i) * 2 * .pi / Float(numPointsH2pi)
                coorY[i] = cos(.pi + thetaH)
                multXZ[i] = sin(thetaH)
            }
        }
    }

    func draw() {
        background(0)
        let cx = width / 2 + map(mouseX, 0, width, -2 * width, 2 * width)
        let cy = height / 2 + map(mouseY, 0, height, -height, height)
        let cz = height / 2 / tan(.pi * 30.0 / 180.0)
        camera(cx, cy, cz, width, height / 2, 0, 0, 1, 0)

        pushMatrix()
        translate(width / 2, height / 2, 0)
        drawTexSphere(200, 200, 200)
        popMatrix()
    }

    func drawTexSphere(_ rx: Float, _ ry: Float, _ rz: Float) {
        let changeU = Float(img.width) / Float(numPointsW - 1)
        let changeV = Float(img.height) / Float(numPointsH - 1)
        var u: Float = 0
        var v: Float = 0

        for i in 0..<(numPointsH - 1) {
            let coory = coorY[i]
            let cooryPlus = coorY[i + 1]
            let mxz = multXZ[i]
            let mxzPlus = multXZ[i + 1]

            beginShape(.triangleStrip)
            texture(img)
            u = 0
            for j in 0..<numPointsW {
                normal(-coorX[j] * mxz, -coory, -coorZ[j] * mxz)
                vertex(coorX[j] * mxz * rx, coory * ry, coorZ[j] * mxz * rz, u, v)
                normal(-coorX[j] * mxzPlus, -cooryPlus, -coorZ[j] * mxzPlus)
                vertex(coorX[j] * mxzPlus * rx, cooryPlus * ry, coorZ[j] * mxzPlus * rz, u, v + changeV)
                u += changeU
            }
            endShape()
            v += changeV
        }
    }

    func keyPressed() {
        if keyCode == .upArrow { ptsH += 1 }
        if keyCode == .downArrow && ptsH > 2 { ptsH -= 1 }
        if keyCode == .leftArrow && ptsW > 1 { ptsW -= 1 }
        if keyCode == .rightArrow { ptsW += 1 }
        initSphere(ptsW, ptsH)
    }
}
