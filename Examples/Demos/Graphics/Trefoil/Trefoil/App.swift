import metaphor

/// Trefoil
///
/// 三葉結び目のパラメトリック曲面を、法線と UV 付きのカスタムシェイプとして
/// `setup()` で 1 度だけ組む。テクスチャは毎フレーム描き足していくので、
/// ジオメトリは据え置いたまま見た目だけが変わっていく。
@main
final class Trefoil: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 1024, height: 768, title: "Trefoil")
    }

    var trefoil: MShape!

    /// 手続き的に描き足していくテクスチャ。
    ///
    /// 原典は `createGraphics()` のオフスクリーン surface に `ellipse()` を打つが、
    /// `MShape.setTexture()` が受けるのは `MImage` だけで `Graphics` は渡せない。
    /// 代わりに `createImage()` + `set()` + `updatePixels()` でピクセルを直接触る。
    /// `updatePixels()` は同じ `MTLTexture` へ書き戻すので、`setTexture()` は
    /// `setup()` で 1 度呼べば以降の変化がそのままシェイプに乗る。
    var tex: MImage!

    func setup() {
        tex = createImage(32, 512)
        // 原典の下地は透明（黒背景に赤い点だけが浮かぶ）だが、それだと曲面の形が
        // まったく読めないので、不透明の暗いグレーを下地にして結び目の面を見せる。
        fillTexture(with: Color(gray: 0.2))
        tex.updatePixels()

        trefoil = createTrefoil(scale: 350, ny: 60, nx: 15)
        trefoil.setTexture(tex)
    }

    func draw() {
        background(0)

        // 毎フレーム 1 点ずつ赤を落として模様を育てる（原典の pg.ellipse に相当）。
        plotDot(
            x: Int(random(0, Float(tex.width))),
            y: Int(random(0, Float(tex.height))),
            radius: 2,
            color: Color(r: 1, g: 0, b: 0, alpha: 1))
        tex.updatePixels()

        lights()
        pointLight(width / 2, height / 2, 400)

        pushMatrix()
        translate(width / 2, height / 2, -200)
        rotateX(Float(frameCount) * PI / 500)
        rotateY(Float(frameCount) * PI / 500)
        shape(trefoil)
        popMatrix()
    }

    // MARK: - Texture

    private func fillTexture(with color: Color) {
        for y in 0..<Int(tex.height) {
            for x in 0..<Int(tex.width) {
                tex.set(x, y, color)
            }
        }
    }

    private func plotDot(x: Int, y: Int, radius: Int, color: Color) {
        for dy in -radius...radius {
            for dx in -radius...radius {
                if dx * dx + dy * dy <= radius * radius {
                    tex.set(x + dx, y + dy, color)
                }
            }
        }
    }

    // MARK: - Geometry

    /// 三葉結び目の曲面を三角形メッシュとして組む。
    ///
    /// 原典 `Surface.pde`（Philip Rideout のパラメトリック曲面の例が元）の移植。
    /// UV は 0〜1 の正規化座標で、metaphor の `vertex(x, y, z, u, v)` はこの流儀
    /// （原典の `textureMode(NORMAL)` に相当する切り替えは不要）。
    private func createTrefoil(scale s: Float, ny: Int, nx: Int) -> MShape {
        let obj = createShape()
        obj.beginShape(.triangles)
        obj.fill(.white)
        obj.noStroke()

        for j in 0..<nx {
            let u0 = Float(j) / Float(nx)
            let u1 = Float(j + 1) / Float(nx)
            for i in 0..<ny {
                let v0 = Float(i) / Float(ny)
                let v1 = Float(i + 1) / Float(ny)

                let p0 = evalPoint(u0, v0)
                let n0 = evalNormal(u0, v0)
                let p1 = evalPoint(u0, v1)
                let n1 = evalNormal(u0, v1)
                let p2 = evalPoint(u1, v1)
                let n2 = evalNormal(u1, v1)

                // 三角形 p0-p1-p2
                appendVertex(obj, s * p0, n0, u0, v0)
                appendVertex(obj, s * p1, n1, u0, v1)
                appendVertex(obj, s * p2, n2, u1, v1)

                let p3 = evalPoint(u1, v0)
                let n3 = evalNormal(u1, v0)

                // 三角形 p0-p2-p3
                appendVertex(obj, s * p0, n0, u0, v0)
                appendVertex(obj, s * p2, n2, u1, v1)
                appendVertex(obj, s * p3, n3, u1, v0)
            }
        }

        obj.endShape()
        return obj
    }

    private func appendVertex(
        _ obj: MShape, _ p: SIMD3<Float>, _ n: SIMD3<Float>, _ u: Float, _ v: Float
    ) {
        obj.normal(n.x, n.y, n.z)  // normal() は次の 1 頂点にだけ効く
        obj.vertex(p.x, p.y, p.z, u, v)
    }

    /// (u, v) に対応する曲面の法線を、2 方向の接線の外積から求める。
    private func evalNormal(_ u: Float, _ v: Float) -> SIMD3<Float> {
        let p = evalPoint(u, v)
        let tangU = evalPoint(u + 0.01, v) - p
        let tangV = evalPoint(u, v + 0.01) - p
        return normalize(cross(tangV, tangU))
    }

    /// (u, v) に対応する曲面上の点。
    private func evalPoint(_ u: Float, _ v: Float) -> SIMD3<Float> {
        let a: Float = 0.5
        let b: Float = 0.3
        let c: Float = 0.5
        let d: Float = 0.1
        let s = TWO_PI * u
        let t = (TWO_PI * (1 - v)) * 2

        let r = a + b * cos(1.5 * t)
        let x = r * cos(t)
        let y = r * sin(t)
        let z = c * sin(1.5 * t)

        let dv = SIMD3<Float>(
            -1.5 * b * sin(1.5 * t) * cos(t) - (a + b * cos(1.5 * t)) * sin(t),
            -1.5 * b * sin(1.5 * t) * sin(t) + (a + b * cos(1.5 * t)) * cos(t),
            1.5 * c * cos(1.5 * t))

        let q = normalize(dv)
        let qvn = normalize(SIMD3<Float>(q.y, -q.x, 0))
        let ww = cross(q, qvn)

        return SIMD3<Float>(
            x + d * (qvn.x * cos(s) + ww.x * sin(s)),
            y + d * (qvn.y * cos(s) + ww.y * sin(s)),
            z + d * ww.z * sin(s))
    }
}
