import Testing
import Metal
@testable import MetaphorNoise

/// 幅・高さのどちらか (または両方) が 1 未満の、グリッドもテクスチャも作れないサイズ。
///
/// ノイズ側は二重に落ちる。負なら `[Float](repeating:0, count:)` が純 Swift の
/// precondition で trap し (Metal を通らない)、0 なら
/// `MTLTextureDescriptor` が `validateWithDevice:` のアサーションでプロセスを終了させる。
/// どちらも `MTLTexture?` / `MImage?` という戻り値では表現できない形の失敗。
private let degenerateSizes: [DegenerateSize] = [
    DegenerateSize(name: "0x0", width: 0, height: 0),
    DegenerateSize(name: "幅だけ 0", width: 0, height: 16),
    DegenerateSize(name: "高さだけ 0", width: 16, height: 0),
    DegenerateSize(name: "幅が負", width: -8, height: 16),
    DegenerateSize(name: "高さが負", width: 16, height: -8),
    DegenerateSize(name: "両方が負", width: -8, height: -8),
]

/// Metal の 2D テクスチャ上限 (16384) を超えるサイズ。
///
/// グリッドの実体を確保させないため、片辺だけを超過させたものに絞る
/// (両辺 65536 だと 16GiB の `[Float]` を先に確保しようとしてしまう)。
private let oversizedSizes: [DegenerateSize] = [
    DegenerateSize(name: "幅だけ超過", width: 16385, height: 4),
    DegenerateSize(name: "高さだけ超過", width: 4, height: 16385),
]

private struct DegenerateSize: Sendable, CustomTestStringConvertible {
    let name: String
    let width: Int
    let height: Int

    var testDescription: String { name }
}

// MARK: - GKNoiseWrapper のグリッド / テクスチャ生成 (Issue #806)

@Suite("ノイズの退化サイズ", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct NoiseDegenerateSizeTests {

    private func makeNoise() -> GKNoiseWrapper {
        GKNoiseWrapper(type: .perlin, config: NoiseConfig(), device: MTLCreateSystemDefaultDevice()!)
    }

    /// `sampleGrid` は Metal を通らずに落ちるため、GPU の有無と無関係に踏める口。
    @Test("sampleGrid が退化サイズで空配列を返す", arguments: degenerateSizes)
    fileprivate func sampleGridReturnsEmpty(size: DegenerateSize) {
        #expect(makeNoise().sampleGrid(width: size.width, height: size.height).isEmpty)
    }

    @Test("texture が退化サイズで nil を返す", arguments: degenerateSizes)
    fileprivate func textureReturnsNil(size: DegenerateSize) {
        #expect(makeNoise().texture(width: size.width, height: size.height) == nil)
    }

    @Test("image が退化サイズで nil を返す", arguments: degenerateSizes)
    fileprivate func imageReturnsNil(size: DegenerateSize) {
        #expect(makeNoise().image(width: size.width, height: size.height) == nil)
    }

    @Test("colorMappedTexture が退化サイズで nil を返す", arguments: degenerateSizes)
    fileprivate func colorMappedTextureReturnsNil(size: DegenerateSize) {
        let stops: [(Float, SIMD4<UInt8>)] = [
            (0, SIMD4(0, 0, 0, 255)), (1, SIMD4(255, 255, 255, 255)),
        ]
        #expect(
            makeNoise().colorMappedTexture(
                width: size.width, height: size.height, colorStops: stops
            ) == nil
        )
    }

    @Test("texture が上限超えで nil を返す", arguments: oversizedSizes)
    fileprivate func textureReturnsNilWhenOversized(size: DegenerateSize) {
        #expect(makeNoise().texture(width: size.width, height: size.height) == nil)
    }

    // MARK: ガードが効きすぎていないこと

    /// 1x1 は退化ではない。境界のすぐ内側が通ることを固定する。
    @Test("1x1 のグリッドとテクスチャは作れる")
    func minimumValidSizeSucceeds() {
        let noise = makeNoise()
        #expect(noise.sampleGrid(width: 1, height: 1).count == 1)
        #expect(noise.texture(width: 1, height: 1) != nil)
        #expect(noise.image(width: 1, height: 1) != nil)
    }

    @Test("実用サイズのグリッドとテクスチャは作れる")
    func typicalSizeSucceeds() {
        let noise = makeNoise()
        #expect(noise.sampleGrid(width: 64, height: 32).count == 64 * 32)
        let tex = noise.texture(width: 64, height: 32)
        #expect(tex?.width == 64)
        #expect(tex?.height == 32)
    }
}
