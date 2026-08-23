import Testing
import Metal
import Foundation
@testable import metaphor
@testable import MetaphorCore
import MetaphorTestSupport

// MARK: - 既定 lights() の向き (#774)

/// 既定リグ ``Canvas3D/lights()`` が**上から差す**ことを固定する。
///
/// シェーダーは `L = normalize(-direction)` で光の来る向きを作り、ワールド +Y は
/// 2D と同じく画面下向き。`directionalLight(0, 1, 0)` が「真上から差す光」と
/// doc で定義されているので、既定の `y` が負だと定義上「真下から」になる。
/// 実際、修正前は上を向いた面が下を向いた面より暗かった。
@Suite("既定 lights() の向き", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct DefaultLightDirectionTests {

    /// 面の向き。カメラから見えなくならないよう 45 度だけ倒す
    /// （±90 度にすると既定カメラからは真横 = 面積 0 になる）。
    private static let tilt: Float = .pi / 4

    /// 白い板を 1 枚だけ描き、フレーム全体の平均輝度を返す。
    ///
    /// 傾きの符号を変えても投影面積は同じなので、平均輝度の大小がそのまま
    /// 「その向きにどれだけ光が当たったか」になる。
    private func meanLuminance(
        rotationX: Float,
        light: @escaping (SketchContext) -> Void
    ) throws -> Float {
        let size = 96
        let image = try OffscreenSketchHarness.render(size: size) { c in
            c.background(0)
            c.noStroke()
            c.fill(255)
            light(c)
            c.translate(c.width / 2, c.height / 2, 0)
            c.rotateX(rotationX)
            c.plane(c.width * 0.7, c.height * 0.7)
        }
        var total = 0
        for i in stride(from: 0, to: image.rgba.count, by: 4) {
            total += Int(image.rgba[i])
        }
        return Float(total) / Float(size * size)
    }

    /// 上を向いた面の傾き。``directionalLight(_:_:_:color:intensity:)`` の doc が
    /// 「`directionalLight(0, 1, 0)` は真上から差す光」と定めているので、その光で
    /// 明るくなる側を「上向き」と定義する（下のテストで実際に確かめる）。
    private static let upFacing: Float = .pi / 4
    private static let downFacing: Float = -.pi / 4

    @Test("真上からの光で明るくなる側を「上向き」と呼べる")
    func upFacingIsLitFromAbove() throws {
        let fromAbove: (SketchContext) -> Void = { c in c.directionalLight(0, 1, 0) }
        let up = try meanLuminance(rotationX: Self.upFacing, light: fromAbove)
        let down = try meanLuminance(rotationX: Self.downFacing, light: fromAbove)
        #expect(up > down, "上向き \(up) / 下向き \(down)")
    }

    @Test("既定の lights() は上を向いた面を下向きより明るくする (regression #774)")
    func defaultRigLitsUpFacingBrighter() throws {
        let rig: (SketchContext) -> Void = { c in c.lights() }
        let up = try meanLuminance(rotationX: Self.upFacing, light: rig)
        let down = try meanLuminance(rotationX: Self.downFacing, light: rig)
        #expect(up > down, "上向き \(up) / 下向き \(down)")
    }

    @Test("既定の lights() は真上からの単灯と同じ側を明るくする (regression #774)")
    func defaultRigAgreesWithLightFromAbove() throws {
        let fromAbove: (SketchContext) -> Void = { c in c.directionalLight(0, 1, 0) }
        let rig: (SketchContext) -> Void = { c in c.lights() }
        let singleUp = try meanLuminance(rotationX: Self.upFacing, light: fromAbove)
        let singleDown = try meanLuminance(rotationX: Self.downFacing, light: fromAbove)
        let rigUp = try meanLuminance(rotationX: Self.upFacing, light: rig)
        let rigDown = try meanLuminance(rotationX: Self.downFacing, light: rig)
        #expect(
            (singleUp > singleDown) == (rigUp > rigDown),
            "単灯 \(singleUp)/\(singleDown) と既定リグ \(rigUp)/\(rigDown) で明暗が逆"
        )
    }

    /// 既定リグは上から差すが、`z` にも成分がある（手前から）ので、正対した面も
    /// アンビエントだけの暗さにはならない。境界として「真下を向いた面より明るい」
    /// ことまでを固定する。
    @Test("既定の lights() で正対した面は下向きより明るい（境界）")
    func defaultRigLitsFrontFacingBrighterThanDownFacing() throws {
        let rig: (SketchContext) -> Void = { c in c.lights() }
        let front = try meanLuminance(rotationX: 0, light: rig)
        let down = try meanLuminance(rotationX: Self.downFacing, light: rig)
        #expect(front > down, "正対 \(front) / 下向き \(down)")
    }
}
