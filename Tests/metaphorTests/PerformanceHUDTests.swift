import Testing
import Metal
import simd
@testable import metaphor
@testable import MetaphorCore

/// パフォーマンス HUD の見た目（Issue #574）。
///
/// HUD が「描かれているのに見えない」状態を防ぐ。チャンネル値をとる
/// `fill(_:_:_:_:)` は `colorMode`（既定の最大値 255）を通るため、0-1 の値で
/// 呼ぶとアルファが 1/255 になり事実上透明になる。
@Suite("PerformanceHUD Appearance", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct PerformanceHUDAppearanceTests {

    private func makeCanvas() throws -> Canvas2D {
        let device = MTLCreateSystemDefaultDevice()!
        return try Canvas2D(
            device: device,
            shaderLibrary: try ShaderLibrary(device: device),
            depthStencilCache: DepthStencilCache(device: device),
            width: 640,
            height: 360
        )
    }

    @Test("パネルと数字の色は見える濃さを持つ")
    func colorsAreVisible() {
        #expect(PerformanceHUD.panelColor.a > 0.5)
        #expect(PerformanceHUD.textColor.a == 1)
        #expect(PerformanceHUD.textColor.g == 1)
    }

    @Test("パネルの塗りが colorMode を通らずそのまま適用される")
    func panelStyleIgnoresColorMode() throws {
        let canvas = try makeCanvas()
        PerformanceHUD.applyPanelStyle(to: canvas)

        #expect(canvas.hasFill)
        #expect(canvas.fillColor == PerformanceHUD.panelColor.simd)
        // 0-1 の値をチャンネル指定で渡していたときのアルファ（0.6/255）に戻らないこと
        #expect(canvas.fillColor.w > 0.5)
    }

    @Test("数字の塗りはスケッチ側の colorMode に左右されない")
    func textStyleIgnoresColorMode() throws {
        let canvas = try makeCanvas()
        // スケッチが HSB 0-1 に切り替えていても HUD の色は変わらない
        canvas.colorMode(.hsb, 1)
        PerformanceHUD.applyTextStyle(to: canvas)

        #expect(canvas.fillColor == PerformanceHUD.textColor.simd)
    }
}
