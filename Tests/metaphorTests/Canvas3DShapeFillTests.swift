import MetaphorTestSupport
import Testing

@testable import MetaphorCore

// MARK: - beginShape3D の fill 適用回数（#825）

/// `beginShape3D` は頂点記録の時点で fill 色を頂点カラーへ焼き込む
/// （`Canvas3D+Shapes.swift`）。頂点シェーダーは `in.color * uniforms.color` を掛けるので、
/// uniforms 側にも fill を送ると `fill²` になる。組み込みプリミティブは頂点カラーが白
/// （`Mesh.swift`）なので 1 回しか掛からず、**同じ板でも組み方で色が変わっていた**（#825）。
///
/// ライトを付けない（`lightCount == 0`）と `metaphorSkipsLighting` が頂点カラーを
/// そのまま返すので、色の掛かり方だけを取り出して測れる。
@Suite("Canvas3D Shape Fill", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct Canvas3DShapeFillTests {

    private static let size = 64

    /// 画面中央に一辺 40 の板を `beginShape3D` で組む。
    ///
    /// Sketch 層の 3D 座標は 2D と同じく左上原点なので、中央へ移動してから組む。
    private func quad(_ ctx: SketchContext, color: Color? = nil) {
        ctx.pushMatrix()
        ctx.translate(Float(Self.size) / 2, Float(Self.size) / 2, 0)
        ctx.beginShape3D()
        if let color {
            ctx.vertex(-20, -20, 0, color)
            ctx.vertex(20, -20, 0, color)
            ctx.vertex(20, 20, 0, color)
            ctx.vertex(-20, 20, 0, color)
        } else {
            ctx.vertex(-20, -20, 0)
            ctx.vertex(20, -20, 0)
            ctx.vertex(20, 20, 0)
            ctx.vertex(-20, 20, 0)
        }
        ctx.endShape3D(.close)
        ctx.popMatrix()
    }

    private func pixel(_ fb: GoldenImage, _ x: Int, _ y: Int) -> SIMD3<Int> {
        let i = (y * fb.width + x) * 4
        return SIMD3(Int(fb.rgba[i]), Int(fb.rgba[i + 1]), Int(fb.rgba[i + 2]))
    }

    private func center(_ fb: GoldenImage) -> SIMD3<Int> {
        pixel(fb, fb.width / 2, fb.height / 2)
    }

    @Test("fill は beginShape3D のシェイプへ 1 回だけ掛かる",
          arguments: [MainPassMode.immediate, .shadows])
    func fillAppliesOnce(mode: MainPassMode) throws {
        let fb = try OffscreenSketchHarness.render(size: Self.size, mode: mode) { ctx in
            ctx.background(Color(r: 0, g: 0, b: 0))
            ctx.noLights()
            ctx.noStroke()
            ctx.fill(Color(r: 0.5, g: 0, b: 0))
            self.quad(ctx)
        }

        let c = center(fb)
        #expect(abs(c.x - 128) <= 8,
                "fill(0.5) の板は 128 前後になるべき（二重に掛かると 64）: \(c) — #825")
    }

    @Test("beginShape3D と plane() が同じ fill 色になる")
    func shapeMatchesPrimitive() throws {
        let shape = try OffscreenSketchHarness.render(size: Self.size) { ctx in
            ctx.background(Color(r: 0, g: 0, b: 0))
            ctx.noLights()
            ctx.noStroke()
            ctx.fill(Color(r: 0.5, g: 0.4, b: 0.2))
            self.quad(ctx)
        }
        let primitive = try OffscreenSketchHarness.render(size: Self.size) { ctx in
            ctx.background(Color(r: 0, g: 0, b: 0))
            ctx.noLights()
            ctx.noStroke()
            ctx.fill(Color(r: 0.5, g: 0.4, b: 0.2))
            ctx.pushMatrix()
            ctx.translate(Float(Self.size) / 2, Float(Self.size) / 2, 0)
            ctx.plane(40, 40)
            ctx.popMatrix()
        }

        let a = center(shape)
        let b = center(primitive)
        #expect(abs(a.x - b.x) <= 4 && abs(a.y - b.y) <= 4 && abs(a.z - b.z) <= 4,
                "同じ寸法・同じ fill なら組み方で色が変わらないべき: shape \(a) / plane \(b) — #825")
    }

    @Test("vertex(x,y,z,color) の色は fill に左右されない")
    func vertexColorIgnoresFill() throws {
        func render(fill: Color) throws -> SIMD3<Int> {
            let fb = try OffscreenSketchHarness.render(size: Self.size) { ctx in
                ctx.background(Color(r: 0, g: 0, b: 0))
                ctx.noLights()
                ctx.noStroke()
                ctx.fill(fill)
                self.quad(ctx, color: Color(r: 0.9, g: 0.25, b: 0.2))
            }
            return center(fb)
        }

        let onWhite = try render(fill: Color(r: 1, g: 1, b: 1))
        let onGray = try render(fill: Color(r: 0.5, g: 0.5, b: 0.5))

        #expect(abs(onWhite.x - 230) <= 8 && abs(onWhite.y - 64) <= 8 && abs(onWhite.z - 51) <= 8,
                "頂点カラーは指定どおり出るべき: \(onWhite) — #825")
        #expect(onWhite == onGray,
                "fill を変えても頂点カラーは変わらないべき: 白 \(onWhite) / 灰 \(onGray) — #825")
    }

    @Test(".points は点ごとの頂点カラーで描かれる",
          arguments: [MainPassMode.immediate, .shadows])
    func pointsKeepOwnColor(mode: MainPassMode) throws {
        let fb = try OffscreenSketchHarness.render(size: Self.size, mode: mode) { ctx in
            ctx.background(Color(r: 0, g: 0, b: 0))
            ctx.noLights()
            ctx.noStroke()
            ctx.fill(Color(r: 1, g: 1, b: 1))
            ctx.translate(Float(Self.size) / 2, Float(Self.size) / 2, 0)
            // 点は 0.5 単位角の三角形なので、拾えるだけの大きさへ拡大する
            ctx.scale(30, 30, 30)
            ctx.beginShape3D(.points)
            ctx.vertex(-0.6, 0, 0, Color(r: 1, g: 0, b: 0))
            ctx.vertex(0.6, 0, 0, Color(r: 0, g: 1, b: 0))
            ctx.endShape3D()
        }

        var red = 0
        var green = 0
        var redSumX = 0
        var greenSumX = 0
        for y in 0..<fb.height {
            for x in 0..<fb.width {
                let p = pixel(fb, x, y)
                if p.x > 120 && p.y < 60 && p.z < 60 { red += 1; redSumX += x }
                if p.y > 120 && p.x < 60 && p.z < 60 { green += 1; greenSumX += x }
            }
        }

        #expect(red > 0 && green > 0,
                "2 点はそれぞれの色で描かれるべき（先頭頂点の色が全点に乗ると片方が消える）: red \(red) / green \(green) — #825")
        if red > 0 && green > 0 {
            #expect(redSumX / red < greenSumX / green,
                    "左が赤・右が緑になるべき: red x \(redSumX / red) / green x \(greenSumX / green)")
        }
    }
}
