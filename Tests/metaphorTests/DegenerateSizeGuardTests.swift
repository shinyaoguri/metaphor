import Testing
import Metal

@testable import metaphor
@testable import MetaphorCore
import MetaphorTestSupport

/// 幅・高さのどちらか (または両方) が 1 未満の、テクスチャを作れないサイズ。
///
/// `MTLTextureDescriptor` はこれらを検証で弾かず `validateWithDevice:` の
/// アサーションでプロセスを終了させる (`Abort trap: 6`)。`throws` でも
/// Optional でも拾えない形の失敗なので、Metal へ渡す前に止める必要がある。
///
/// `@Test(arguments:)` は Suite の外 (nonisolated) から評価されるため、
/// `@MainActor` な Suite の static プロパティには置けない。
private let degenerateSizes: [DegenerateSize] = [
    DegenerateSize(name: "0x0", width: 0, height: 0),
    DegenerateSize(name: "幅だけ 0", width: 0, height: 16),
    DegenerateSize(name: "高さだけ 0", width: 16, height: 0),
    DegenerateSize(name: "幅が負", width: -8, height: 16),
    DegenerateSize(name: "高さが負", width: 16, height: -8),
    DegenerateSize(name: "両方が負", width: -8, height: -8),
]

private struct DegenerateSize: Sendable, CustomTestStringConvertible {
    let name: String
    let width: Int
    let height: Int

    var testDescription: String { name }
}

// MARK: - テクスチャを持つ生成 API が退化サイズで落ちない (Issue #798)

/// `createGraphics` / `createGraphics3D` は戻り値が `Graphics?` / `Graphics3D?` で
/// 失敗しうることを型が宣言しているのに、修正前は `nil` ではなくプロセスの即死として
/// 失敗が出てきた。`guard let` を書いている呼び出し側からは守れない形だった。
@Suite("退化サイズのガード", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct DegenerateSizeGuardTests {

    private func makeContext() throws -> SketchContext {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        return SketchContext(
            renderer: renderer,
            canvas: try Canvas2D(renderer: renderer),
            canvas3D: try Canvas3D(renderer: renderer),
            input: renderer.input
        )
    }

    // MARK: 根本の防壁

    /// `Graphics` / `Graphics3D` / メインキャンバスが共通で通る唯一の関門。
    @Test("TextureManager が退化サイズを throw で弾く", arguments: degenerateSizes)
    fileprivate func textureManagerThrows(size: DegenerateSize) throws {
        #expect(throws: MetaphorError.self) {
            _ = try TextureManager(
                device: MetalTestHelper.device!,
                width: size.width,
                height: size.height,
                sampleCount: 1
            )
        }
    }

    @Test("Graphics の init が退化サイズを throw で弾く", arguments: degenerateSizes)
    fileprivate func graphicsInitThrows(size: DegenerateSize) throws {
        let shaderLib = try MetalTestHelper.shaderLibrary()
        let depthCache = MetalTestHelper.depthStencilCache()
        #expect(throws: MetaphorError.self) {
            _ = try Graphics(
                device: MetalTestHelper.device!,
                commandQueue: MetalTestHelper.commandQueue()!,
                shaderLibrary: shaderLib,
                depthStencilCache: depthCache,
                width: size.width,
                height: size.height
            )
        }
    }

    @Test("Graphics3D の init が退化サイズを throw で弾く", arguments: degenerateSizes)
    fileprivate func graphics3DInitThrows(size: DegenerateSize) throws {
        let shaderLib = try MetalTestHelper.shaderLibrary()
        let depthCache = MetalTestHelper.depthStencilCache()
        #expect(throws: MetaphorError.self) {
            _ = try Graphics3D(
                device: MetalTestHelper.device!,
                commandQueue: MetalTestHelper.commandQueue()!,
                shaderLibrary: shaderLib,
                depthStencilCache: depthCache,
                width: size.width,
                height: size.height
            )
        }
    }

    // MARK: 公開 API から見た振る舞い

    @Test("createGraphics が退化サイズで nil を返す", arguments: degenerateSizes)
    fileprivate func createGraphicsReturnsNil(size: DegenerateSize) throws {
        let context = try makeContext()
        #expect(context.createGraphics(size.width, size.height) == nil)
    }

    @Test("createGraphics3D が退化サイズで nil を返す", arguments: degenerateSizes)
    fileprivate func createGraphics3DReturnsNil(size: DegenerateSize) throws {
        let context = try makeContext()
        #expect(context.createGraphics3D(size.width, size.height) == nil)
    }

    /// `SketchContext.createImage` の入り口ガードは修正前からあるが、
    /// `TextureManager` を通らず自前で descriptor を組むこの `public static` 版には
    /// 無かった。context を経由しない呼び出しが同じ形で落ちる口が残っていた。
    @Test("MImage.createImage(device:) が退化サイズで nil を返す", arguments: degenerateSizes)
    fileprivate func createImageReturnsNil(size: DegenerateSize) throws {
        #expect(MImage.createImage(size.width, size.height, device: MetalTestHelper.device!) == nil)
    }

    // MARK: ガードが効きすぎていないこと

    /// 1x1 は退化ではない。境界のすぐ内側が通ることを固定する。
    @Test("1x1 は作れる")
    func minimumValidSizeSucceeds() throws {
        let context = try makeContext()
        #expect(context.createGraphics(1, 1) != nil)
        #expect(context.createGraphics3D(1, 1) != nil)
        #expect(MImage.createImage(1, 1, device: MetalTestHelper.device!) != nil)
    }
}
