import metaphor

/// Wiggling
///
/// リテインドシェイプの頂点を毎フレーム書き換えるデモ。`w` で揺れをトグル、
/// スペースで元の位置に戻す。ジオメトリは `setup()` で 1 度だけ組み、
/// 以降は `setVertex()` で座標だけを差し替える。
@main
final class Wiggling: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 1024, height: 768, title: "Wiggling")
    }

    let cubeSize: Float = 320
    let circleRad: Float = 100
    let circleRes = 40
    let noiseMag: Float = 1

    /// 6 面をぶら下げたグループ。面ごとに向きが違うので 1 メッシュには畳まない
    /// （子は 6 つだけなのでドローコールも 6 で済む）。
    var cube: MShape!

    var wiggling = false

    func setup() {
        createCube()
    }

    func draw() {
        background(0)

        // 原典は面を赤いストロークで縁取って立体を読ませるが、リテインドな 3D
        // カスタムシェイプは塗りメッシュしか描かない（ストローク経路が無い）。
        // 代わりにライティングで面の向きを出す。
        lights()

        pushMatrix()
        translate(width / 2, height / 2)
        rotateX(Float(frameCount) * 0.01)
        rotateY(Float(frameCount) * 0.01)
        shape(cube)
        popMatrix()

        if wiggling {
            wiggleVertices()
        }

        fill(.white)
        textSize(14)
        text(wiggling ? "wiggling — press SPACE to restore" : "press 'w' to wiggle", 10, 20)
    }

    func keyPressed() {
        guard let key else { return }
        switch key {
        case "w":
            wiggling.toggle()
        case " ":
            wiggling = false
            restoreCube()
        default:
            break
        }
    }

    // MARK: - Geometry

    /// 面の頂点を 1 つずつランダムにずらす。
    ///
    /// `setVertex()` はシェイプをダーティにするので、次の描画でメッシュが組み直される。
    /// ここが「リテインドでも中身は書き換えられる」ことを見せる本題。
    private func wiggleVertices() {
        for i in 0..<cube.childCount {
            guard let face = cube.getChild(i) else { continue }
            for j in 0..<face.vertexCount {
                guard let p = face.getVertex(j) else { continue }
                face.setVertex(
                    j,
                    p.x + random(-noiseMag / 2, noiseMag / 2),
                    p.y + random(-noiseMag / 2, noiseMag / 2),
                    p.z + random(-noiseMag / 2, noiseMag / 2))
            }
        }
    }

    /// 前面の形で 6 面を作り、回転で立方体の各面へ配置する。
    ///
    /// 原典と同じく面のローカル変換（`rotateX` / `rotateY`）で向きを決めるので、
    /// `restoreCube()` は頂点座標だけを戻せばよい（向きは保たれる）。
    private func createCube() {
        cube = createShape(.group)
        for _ in 0..<6 {
            cube.addChild(makeFace())
        }

        cube.getChild(1)?.rotateY(radians(180))  // 背面
        cube.getChild(2)?.rotateY(radians(90))  // 右面
        cube.getChild(3)?.rotateY(radians(-90))  // 左面
        cube.getChild(4)?.rotateX(radians(90))  // 上面
        cube.getChild(5)?.rotateX(radians(-90))  // 下面
    }

    private func makeFace() -> MShape {
        let s = createShape()
        s.beginShape(.triangles)
        s.fill(.white)
        s.noStroke()
        let z = cubeSize / 2
        for p in facePositions() {
            s.normal(0, 0, 1)  // normal() は次の 1 頂点にだけ効く
            s.vertex(p.x, p.y, z)
        }
        s.endShape()
        return s
    }

    private func restoreCube() {
        let z = cubeSize / 2
        let positions = facePositions()
        for i in 0..<cube.childCount {
            guard let face = cube.getChild(i) else { continue }
            for (j, p) in positions.enumerated() {
                face.setVertex(j, p.x, p.y, z)
            }
        }
    }

    /// 穴あきの面を三角形の並びとして返す（1 三角形 = 3 要素、`.triangles` 順）。
    ///
    /// 原典は `beginContour()` で四角に円の穴を開けるが、metaphor の
    /// `beginContour()` は 2D シェイプ専用で（`vertices2D` にしか範囲を持たない）、
    /// 3D の `.polygon` はファン分割なので穴を表現できない。同じ絵を出すため、
    /// 内側の円と外側の四角のあいだを輪帯として自前で三角形に割る。
    private func facePositions() -> [SIMD2<Float>] {
        var out: [SIMD2<Float>] = []
        out.reserveCapacity(circleRes * 6)
        for i in 0..<circleRes {
            let a0 = TWO_PI * Float(i) / Float(circleRes)
            let a1 = TWO_PI * Float(i + 1) / Float(circleRes)
            let in0 = innerPoint(a0)
            let in1 = innerPoint(a1)
            let out0 = outerPoint(a0)
            let out1 = outerPoint(a1)
            out.append(contentsOf: [in0, in1, out1, in0, out1, out0])
        }
        return out
    }

    private func innerPoint(_ angle: Float) -> SIMD2<Float> {
        SIMD2(circleRad * sin(angle), circleRad * cos(angle))
    }

    /// 中心から `angle` 方向へ伸ばした半直線が、面の四角形の縁と交わる点。
    private func outerPoint(_ angle: Float) -> SIMD2<Float> {
        let d = SIMD2(sin(angle), cos(angle))
        let half = cubeSize / 2
        let t = half / max(abs(d.x), abs(d.y))
        return d * t
    }
}
