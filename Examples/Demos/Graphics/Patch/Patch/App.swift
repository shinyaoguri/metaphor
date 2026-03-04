import metaphor
import Foundation

@main
final class Patch: Sketch {
    var config: SketchConfig {
        SketchConfig(title: "Patch", width: 1024, height: 768)
    }

    let ni = 4
    let nj = 5
    var RESI: Int { ni * 10 }
    var RESJ: Int { nj * 10 }

    var outp: [[(Float, Float, Float)]] = []
    var normp: [[(Float, Float, Float)]] = []
    var inp: [[(Float, Float, Float)]] = []

    func setup() {
        build()
    }

    func draw() {
        background(255)
        translate(width / 2, height / 2)
        lights()
        scale(0.9)
        rotateY(map(mouseX, 0, width, -.pi, .pi))
        rotateX(map(mouseY, 0, height, -.pi, .pi))

        noStroke()
        fill(255)
        for i in 0..<(RESI - 1) {
            beginShape(.triangleStrip)
            for j in 0..<RESJ {
                let n = normp[i][j]
                normal(n.0, n.1, n.2)
                let p1 = outp[i][j]
                vertex(p1.0, p1.1, p1.2)
                let p2 = outp[i + 1][j]
                vertex(p2.0, p2.1, p2.2)
            }
            endShape()
        }
    }

    func keyPressed() {
        if key == " " { build() }
    }

    func build() {
        // Initialize control points
        inp = Array(repeating: Array(repeating: (Float(0), Float(0), Float(0)), count: nj + 1), count: ni + 1)
        for i in 0...ni {
            for j in 0...nj {
                inp[i][j] = (Float(i), Float(j), Float.random(in: -3...3))
            }
        }

        outp = Array(repeating: Array(repeating: (Float(0), Float(0), Float(0)), count: RESJ), count: RESI)
        normp = Array(repeating: Array(repeating: (Float(0), Float(0), Float(0)), count: RESJ), count: RESI)

        for i in 0..<RESI {
            let mui = Double(i) / Double(RESI - 1)
            for j in 0..<RESJ {
                let muj = Double(j) / Double(RESJ - 1)
                var ox: Double = 0, oy: Double = 0, oz: Double = 0
                var utx: Double = 0, uty: Double = 0, utz: Double = 0
                var vtx: Double = 0, vty: Double = 0, vtz: Double = 0

                for ki in 0...ni {
                    let bi = bezierBlend(ki, mui, ni)
                    let dbi = dBezierBlend(ki, mui, ni)
                    for kj in 0...nj {
                        let bj = bezierBlend(kj, muj, nj)
                        let dbj = dBezierBlend(kj, muj, nj)
                        let pt = inp[ki][kj]
                        ox += Double(pt.0) * bi * bj
                        oy += Double(pt.1) * bi * bj
                        oz += Double(pt.2) * bi * bj
                        utx += Double(pt.0) * dbi * bj
                        uty += Double(pt.1) * dbi * bj
                        utz += Double(pt.2) * dbi * bj
                        vtx += Double(pt.0) * bi * dbj
                        vty += Double(pt.1) * bi * dbj
                        vtz += Double(pt.2) * bi * dbj
                    }
                }

                ox -= Double(ni) / 2; oy -= Double(nj) / 2
                ox *= 100; oy *= 100; oz *= 100
                outp[i][j] = (Float(ox), Float(oy), Float(oz))

                // Cross product for normal
                let nx = uty * vtz - utz * vty
                let ny = utz * vtx - utx * vtz
                let nz = utx * vty - uty * vtx
                let nl = sqrt(nx * nx + ny * ny + nz * nz)
                if nl > 0 {
                    normp[i][j] = (Float(nx / nl), Float(ny / nl), Float(nz / nl))
                } else {
                    normp[i][j] = (0, 0, 1)
                }
            }
        }
    }

    func bezierBlend(_ k: Int, _ mu: Double, _ n: Int) -> Double {
        var blend: Double = 1
        var nn = n, kn = k, nkn = n - k
        while nn >= 1 {
            blend *= Double(nn)
            nn -= 1
            if kn > 1 { blend /= Double(kn); kn -= 1 }
            if nkn > 1 { blend /= Double(nkn); nkn -= 1 }
        }
        if k > 0 { blend *= pow(mu, Double(k)) }
        if n - k > 0 { blend *= pow(1 - mu, Double(n - k)) }
        return blend
    }

    func dBezierBlend(_ k: Int, _ mu: Double, _ n: Int) -> Double {
        var dblendf: Double = 1
        var nn = n, kn = k, nkn = n - k
        while nn >= 1 {
            dblendf *= Double(nn)
            nn -= 1
            if kn > 1 { dblendf /= Double(kn); kn -= 1 }
            if nkn > 1 { dblendf /= Double(nkn); nkn -= 1 }
        }
        var fk: Double = 1, dk: Double = 0
        var fnk: Double = 1, dnk: Double = 0
        if k > 0 { fk = pow(mu, Double(k)); dk = Double(k) * pow(mu, Double(k - 1)) }
        if n - k > 0 { fnk = pow(1 - mu, Double(n - k)); dnk = Double(k - n) * pow(1 - mu, Double(n - k - 1)) }
        dblendf *= (dk * fnk + fk * dnk)
        return dblendf
    }
}
