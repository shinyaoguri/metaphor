import Testing
import Metal
import MetaphorCore
@testable import MetaphorCoreImage

/// 幅・高さのどちらか (または両方) が 1 未満の、テクスチャを作れないサイズ。
///
/// `MTLTextureDescriptor` はこれらを検証で弾かず `validateWithDevice:` の
/// アサーションでプロセスを終了させる (`Abort trap: 6`)。`MTLTexture?` /
/// `MImage?` という戻り値では表現できない形の失敗。
private let degenerateSizes: [DegenerateSize] = [
    DegenerateSize(name: "0x0", width: 0, height: 0),
    DegenerateSize(name: "幅だけ 0", width: 0, height: 16),
    DegenerateSize(name: "高さだけ 0", width: 16, height: 0),
    DegenerateSize(name: "幅が負", width: -8, height: 16),
    DegenerateSize(name: "高さが負", width: 16, height: -8),
    DegenerateSize(name: "両方が負", width: -8, height: -8),
]

/// Metal の 2D テクスチャ上限 (``TextureManager/maxDimension``) を超えるサイズ。
private let oversizedSizes: [DegenerateSize] = [
    DegenerateSize(name: "上限 + 1", width: 16385, height: 16385),
    DegenerateSize(name: "65536 角", width: 65536, height: 65536),
    DegenerateSize(name: "幅だけ超過", width: 65536, height: 480),
    DegenerateSize(name: "高さだけ超過", width: 640, height: 65536),
]

private struct DegenerateSize: Sendable, CustomTestStringConvertible {
    let name: String
    let width: Int
    let height: Int

    var testDescription: String { name }
}

// MARK: - CIFilterWrapper.generate の出力テクスチャ (Issue #806)

/// `ciGenerate(_:width:height:)` は `MImage?` を返すので「失敗しうる」と型が宣言しているのに、
/// 修正前は `getOrCreateTexture` が退化サイズをそのまま `MTLTextureDescriptor` へ渡し、
/// `guard let` を書いている呼び出し側では守れない abort になっていた。
@Suite("CIFilterWrapper の退化サイズ", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct CIFilterWrapperDegenerateSizeTests {

    private func makeWrapper() -> CIFilterWrapper {
        let device = MTLCreateSystemDefaultDevice()!
        return CIFilterWrapper(device: device, commandQueue: device.makeCommandQueue()!)
    }

    @Test("generate が退化サイズで nil を返す", arguments: degenerateSizes)
    fileprivate func generateReturnsNil(size: DegenerateSize) {
        let preset = CIFilterPreset.checkerboard()
        #expect(
            makeWrapper().generate(
                filterName: preset.filterName,
                parameters: preset.parameters(
                    textureSize: CGSize(width: size.width, height: size.height)
                ),
                width: size.width,
                height: size.height
            ) == nil
        )
    }

    @Test("generate が上限超えで nil を返す", arguments: oversizedSizes)
    fileprivate func generateReturnsNilWhenOversized(size: DegenerateSize) {
        let preset = CIFilterPreset.checkerboard()
        #expect(
            makeWrapper().generate(
                filterName: preset.filterName,
                parameters: preset.parameters(
                    textureSize: CGSize(width: size.width, height: size.height)
                ),
                width: size.width,
                height: size.height
            ) == nil
        )
    }

    // MARK: ガードが効きすぎていないこと

    @Test("正当なサイズは生成できる", arguments: [(1, 1), (64, 32)])
    func validSizeSucceeds(size: (width: Int, height: Int)) {
        let preset = CIFilterPreset.checkerboard()
        let tex = makeWrapper().generate(
            filterName: preset.filterName,
            parameters: preset.parameters(
                textureSize: CGSize(width: size.width, height: size.height)
            ),
            width: size.width,
            height: size.height
        )
        #expect(tex?.width == size.width)
        #expect(tex?.height == size.height)
    }
}
