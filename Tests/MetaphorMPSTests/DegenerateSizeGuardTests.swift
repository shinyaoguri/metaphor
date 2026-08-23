import Testing
import Metal
@testable import MetaphorCore
@testable import MetaphorMPS

/// 幅・高さのどちらか (または両方) が 1 未満の、テクスチャを作れないサイズ。
///
/// `MTLTextureDescriptor` はこれらを検証で弾かず `validateWithDevice:` の
/// アサーションでプロセスを終了させる (`Abort trap: 6`)。`throws` でも
/// Optional でも拾えない形の失敗なので、Metal へ渡す前に止める必要がある。
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

// MARK: - MPSRayTracer の出力テクスチャ (Issue #806)

/// `createRayTracer(width:height:)` は `throws` なので「失敗しうる」と型が宣言しているのに、
/// 修正前は `setupOutputTexture()` が退化サイズをそのまま `MTLTextureDescriptor` へ渡し、
/// `try` を書いている呼び出し側では捕まえられない abort になっていた。
@Suite("MPSRayTracer の退化サイズ", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct MPSRayTracerDegenerateSizeTests {

    @Test("退化サイズは throw で弾かれる", arguments: degenerateSizes)
    fileprivate func degenerateSizeThrows(size: DegenerateSize) throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        #expect(throws: MetaphorError.self) {
            _ = try MPSRayTracer(
                device: device, commandQueue: queue, width: size.width, height: size.height
            )
        }
    }

    @Test("上限を超えるサイズは throw で弾かれる", arguments: oversizedSizes)
    fileprivate func oversizedThrows(size: DegenerateSize) throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        #expect(throws: MetaphorError.self) {
            _ = try MPSRayTracer(
                device: device, commandQueue: queue, width: size.width, height: size.height
            )
        }
    }

    /// ガードが効きすぎていないこと。1x1 も上限内の実用サイズも通る。
    @Test("正当なサイズはそのまま作れる", arguments: [(1, 1), (64, 64), (1920, 1080)])
    func validSizeSucceeds(size: (width: Int, height: Int)) throws {
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let rt = try MPSRayTracer(
            device: device, commandQueue: queue, width: size.width, height: size.height
        )
        #expect(rt.outputTexture?.width == size.width)
        #expect(rt.outputTexture?.height == size.height)
    }
}
