import metaphor

/// StaticParticlesRetained
///
/// Retained mode: the particle geometry is built once in `setup()` and redrawn with a
/// single `shape()` call per frame. Compare with `StaticParticlesImmediate`, which
/// re-submits every particle each frame.
@main
final class StaticParticlesRetained: Sketch {
    var config: SketchConfig {
        SketchConfig(width: 800, height: 600, title: "StaticParticlesRetained")
    }

    // 対の StaticParticlesImmediate と同じ条件（粒子数は原典と同じ 50,000 / #680）。
    // partSize だけ原典の 20 から落としてある: 原典は半透明スプライトを重ねるが
    // metaphor 版は不透明の単色なので、20 のままだと画面が白い塊で埋まる。
    let npartTotal = 50000
    let partSize: Float = 3

    /// 全パーティクルを 1 つのメッシュに詰めたシェイプ。
    var particles: MShape!

    var fcount = 0
    var lastm = 0
    var frate: Float = 0
    let fint = 3

    func setup() {
        frameRate(60)
        particles = makeParticles()
    }

    func draw() {
        background(0)

        // HUD が回転・平行移動を引きずらないよう、パーティクルの変換は push/pop で閉じる。
        pushMatrix()
        translate(width / 2, height / 2)
        rotateY(Float(frameCount) * 0.01)
        // ジオメトリは setup() で確定済み。毎フレームの描画はこの 1 行だけ。
        shape(particles)
        popMatrix()

        fcount += 1
        let m = millis()
        if m - lastm > 1000 * fint {
            frate = Float(fcount) / Float(fint)
            fcount = 0
            lastm = m
        }
        fill(255)
        textSize(14)
        text("fps: \(Int(frate))", 10, 20)
    }

    // MARK: - Geometry

    /// 全パーティクルの三角形を 1 つの `.path3D` シェイプに詰める。
    ///
    /// 原典 `.pde` は `createShape(PShape.GROUP)` に 1 粒子 1 子シェイプを `addChild` するが、
    /// metaphor の `.group` は 1 本の VBO に畳まれず子を 1 つずつ描く
    /// （`Sources/MetaphorCore/Drawing/MShapeDrawing.swift` の `case .group:`）。
    /// つまり子シェイプに分けると粒子数ぶんのメッシュ・ドローコールになり、即時描画と
    /// 同じコストに戻る（実測 50,000 粒子 / 800x600 / Apple Silicon / release / `frameRate(60)`:
    /// 即時 ≒ 32 fps、`.group` + `addChild` も即時と同程度、この 1 メッシュ版は 60 fps
    /// 上限に張り付いたまま）。
    /// retained の利点を出すにはこのように 1 シェイプへまとめる。
    private func makeParticles() -> MShape {
        let s = createShape()
        s.beginShape(.triangles)  // ShapeMode に .quads は無いので 1 quad = 2 三角形で表す
        s.fill(.white)
        s.noStroke()
        for _ in 0..<npartTotal {
            appendQuad(
                to: s,
                center: SIMD3(random(-500, 500), random(-500, 500), random(-500, 500)))
        }
        s.endShape()
        return s
    }

    /// XY 平面に平行な四角形（2 三角形）を追加する。原典と同じくビルボードではないので、
    /// rotateY が 90 度に近づくと板が edge-on になって細く見える。
    ///
    /// - Note: 3 引数の `vertex` を呼んだ時点でシェイプが `.path3D` になる。2 引数のままだと
    ///   `.path2D` 扱いになり 3D 変換が効かない。
    /// - Note: 原典は半透明スプライト + `hint(DISABLE_DEPTH_MASK)` だが、metaphor には
    ///   深度書き込みを切る公開 API が無いため不透明の単色 fill にしている
    ///   （対の StaticParticlesImmediate も `data/sprite.png` を使っていない）。
    private func appendQuad(to s: MShape, center c: SIMD3<Float>) {
        let h = partSize / 2
        let corners: [SIMD2<Float>] = [
            SIMD2(-h, -h), SIMD2(h, -h), SIMD2(h, h),
            SIMD2(-h, -h), SIMD2(h, h), SIMD2(-h, h),
        ]
        s.normal(0, 0, 1)  // 以降の頂点に持続する（原典と同じ 1 回）
        for o in corners {
            s.vertex(c.x + o.x, c.y + o.y, c.z)
        }
    }
}
