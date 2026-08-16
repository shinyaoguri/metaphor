import MetaphorTestSupport
import Testing
import simd

@testable import MetaphorCore

// MARK: - .lines / .points の色は stroke が決める（#739）

/// `beginShape3D(.lines)` / `beginShape3D(.points)` が `stroke()` の色で描かれることを
/// 画素で固定する（#739）。
///
/// 頂点は記録の時点で色を焼き込む（`Canvas3D+Shapes.swift`）。線・点のモードでも
/// `fill` を焼き込んでいたため、`stroke(緑)` を指定しても塗りは fill 色のままだった。
/// Processing では LINES / POINTS の色を決めるのは `stroke()` なので、線・点のモードでは
/// stroke 色を焼き込む。`vertex(x, y, z, color)` で**明示した頂点カラーは今までどおり勝つ**
/// （#825 の点ごとの色分けを保つため）。
///
/// あわせて `.points` の経路差も固定する。イミディエイトの `drawShape3DPoints()` は
/// 独自のエンコードを持っていてストロークパスが無く、記録経路（影オン）はストロークパスを
/// 通っていたので、**同じスケッチが `shadows()` の有無で別の絵になっていた**。
@Suite("Canvas3D Shape Stroke Color", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct Canvas3DShapeStrokeColorTests {

    private static let size = 64

    /// 非黒画素を「赤寄り」「緑寄り」に数える。
    private func tally(_ fb: GoldenImage) -> (red: Int, green: Int, other: Int) {
        var red = 0, green = 0, other = 0
        for y in 0..<fb.height {
            for x in 0..<fb.width {
                let i = (y * fb.width + x) * 4
                let r = Int(fb.rgba[i]), g = Int(fb.rgba[i + 1]), b = Int(fb.rgba[i + 2])
                if r + g + b == 0 { continue }
                if r > 32 && g <= 32 && b <= 32 { red += 1 } else if g > 32 && r <= 32 && b <= 32 {
                    green += 1
                } else {
                    other += 1
                }
            }
        }
        return (red, green, other)
    }

    /// 画面中央に水平線を 1 本引く。
    ///
    /// 線分は 0.5 単位幅の細い四角形で、等倍だとスクリーン上で 1 画素に満たない。
    /// そのままだとストロークパスのワイヤーフレームが四角形を覆い隠してしまい、
    /// 塗りに何色が乗っているかを測れない。線幅が数画素になるまで拡大して、
    /// **内側**の色を見えるようにする（#739 の症状が出るのはこの状態）。
    private func line(_ ctx: SketchContext) {
        ctx.pushMatrix()
        ctx.translate(Float(Self.size) / 2, Float(Self.size) / 2, 0)
        ctx.scale(8, 8, 8)
        ctx.beginShape3D(.lines)
        ctx.vertex(-3, 0, 0)
        ctx.vertex(3, 0, 0)
        ctx.endShape3D()
        ctx.popMatrix()
    }

    /// 画面中央に点を 1 つ置く（0.5 単位角の三角形なので拾えるまで拡大する）。
    private func point(_ ctx: SketchContext) {
        ctx.pushMatrix()
        ctx.translate(Float(Self.size) / 2, Float(Self.size) / 2, 0)
        ctx.scale(30, 30, 30)
        ctx.beginShape3D(.points)
        ctx.vertex(0, 0, 0)
        ctx.endShape3D()
        ctx.popMatrix()
    }

    @Test(".lines は fill ではなく stroke の色で描かれる",
          arguments: [MainPassMode.immediate, .shadows])
    func linesUseStrokeColor(mode: MainPassMode) throws {
        let fb = try OffscreenSketchHarness.render(size: Self.size, mode: mode) { ctx in
            ctx.background(Color(r: 0, g: 0, b: 0))
            ctx.noLights()
            ctx.fill(Color(r: 1, g: 0, b: 0))
            ctx.stroke(Color(r: 0, g: 1, b: 0))
            self.line(ctx)
        }

        let t = tally(fb)
        #expect(t.green > 0, "線が描かれていない: \(t) — #739")
        #expect(t.red == 0, "線に fill 色（赤）が残っている: \(t) — #739")
    }

    @Test(".points は fill ではなく stroke の色で描かれる",
          arguments: [MainPassMode.immediate, .shadows])
    func pointsUseStrokeColor(mode: MainPassMode) throws {
        let fb = try OffscreenSketchHarness.render(size: Self.size, mode: mode) { ctx in
            ctx.background(Color(r: 0, g: 0, b: 0))
            ctx.noLights()
            ctx.fill(Color(r: 1, g: 0, b: 0))
            ctx.stroke(Color(r: 0, g: 1, b: 0))
            self.point(ctx)
        }

        let t = tally(fb)
        #expect(t.green > 0, "点が描かれていない: \(t) — #739")
        #expect(t.red == 0, "点に fill 色（赤）が残っている: \(t) — #739")
    }

    @Test(".points の絵はイミディエイトと記録経路で一致する")
    func pointsMatchAcrossModes() throws {
        func render(_ mode: MainPassMode) throws -> GoldenImage {
            try OffscreenSketchHarness.render(size: Self.size, mode: mode) { ctx in
                ctx.background(Color(r: 0, g: 0, b: 0))
                ctx.noLights()
                ctx.fill(Color(r: 1, g: 0, b: 0))
                ctx.stroke(Color(r: 0, g: 1, b: 0))
                self.point(ctx)
            }
        }

        let immediate = tally(try render(.immediate))
        let shadows = tally(try render(.shadows))

        // 完全一致まで求めるとストロークの深度バイアス由来の 1 画素差で折れるので、
        // 「どちらの色がどれだけ出るか」で比べる（fill 色一色 ↔ fill+stroke 混在は桁で違う）
        #expect(immediate.red == shadows.red && immediate.green > 0 && shadows.green > 0,
                "shadows() の有無で .points の絵が変わる: immediate \(immediate) / shadows \(shadows) — #739")
    }

    @Test("明示した頂点カラーは stroke より優先される（#825 を保つ）",
          arguments: [MainPassMode.immediate, .shadows])
    func explicitVertexColorWinsOverStroke(mode: MainPassMode) throws {
        let fb = try OffscreenSketchHarness.render(size: Self.size, mode: mode) { ctx in
            ctx.background(Color(r: 0, g: 0, b: 0))
            ctx.noLights()
            ctx.fill(Color(r: 1, g: 1, b: 1))
            ctx.stroke(Color(r: 0, g: 1, b: 0))
            ctx.pushMatrix()
            ctx.translate(Float(Self.size) / 2, Float(Self.size) / 2, 0)
            ctx.scale(30, 30, 30)
            ctx.beginShape3D(.points)
            ctx.vertex(0, 0, 0, Color(r: 1, g: 0, b: 0))
            ctx.endShape3D()
            ctx.popMatrix()
        }

        let t = tally(fb)
        #expect(t.red > 0,
                "vertex(x, y, z, color) の赤が stroke 色に潰されている: \(t) — #825 / #739")
    }

    @Test("noStroke() の .lines / .points は従来どおり fill 色で描かれる",
          arguments: [MainPassMode.immediate, .shadows])
    func noStrokeFallsBackToFill(mode: MainPassMode) throws {
        let fb = try OffscreenSketchHarness.render(size: Self.size, mode: mode) { ctx in
            ctx.background(Color(r: 0, g: 0, b: 0))
            ctx.noLights()
            ctx.fill(Color(r: 1, g: 0, b: 0))
            ctx.noStroke()
            self.point(ctx)
        }

        let t = tally(fb)
        #expect(t.red > 0 && t.green == 0,
                "noStroke() のときは fill 色で描かれるべき: \(t) — #739")
    }
}
