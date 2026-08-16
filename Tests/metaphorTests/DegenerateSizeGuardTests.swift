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

/// Metal の 2D テクスチャ上限 (``TextureManager/maxDimension``) を超えるサイズ。
///
/// 退化サイズ (0 以下) と同じく `MTLTextureDescriptor` の検証を通らず、
/// `makeTexture` の `nil` ではなく `validateWithDevice:` のアサーションで
/// プロセスが終了する ("greater than the maximum allowed size of 16384")。
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

// MARK: - 上限を超えるサイズも同じ口で止める (Issue #842)

/// 下限 (#798) と違い、上限のチェックはリポジトリのどこにも無かった。
/// `guard width > 0` を通った 65536 はそのまま `MTLTextureDescriptor` へ行き、
/// `createWindow` / `createGraphics` の「失敗したら `nil`」という契約を裏切って
/// プロセスごと abort していた。
@Suite("上限サイズのガード", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct OversizedGuardTests {

    private func makeContext() throws -> SketchContext {
        let renderer = try MetaphorRenderer(width: 32, height: 32)
        return SketchContext(
            renderer: renderer,
            canvas: try Canvas2D(renderer: renderer),
            canvas3D: try Canvas3D(renderer: renderer),
            input: renderer.input
        )
    }

    @Test("上限は Apple Silicon の 16384")
    func maxDimensionIsDocumented() {
        #expect(TextureManager.maxDimension == 16384)
    }

    @Test("TextureManager が上限超えを throw で弾く", arguments: oversizedSizes)
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

    @Test("createGraphics が上限超えで nil を返す", arguments: oversizedSizes)
    fileprivate func createGraphicsReturnsNil(size: DegenerateSize) throws {
        let context = try makeContext()
        #expect(context.createGraphics(size.width, size.height) == nil)
    }

    @Test("createGraphics3D が上限超えで nil を返す", arguments: oversizedSizes)
    fileprivate func createGraphics3DReturnsNil(size: DegenerateSize) throws {
        let context = try makeContext()
        #expect(context.createGraphics3D(size.width, size.height) == nil)
    }

    /// ガードが効きすぎていないこと。上限ちょうど (16384 角) は色 + 深度で 2GiB を
    /// 確保するためテストでは作らず、じゅうぶん大きい実用サイズで代用する。
    @Test("上限内の大きなサイズは作れる")
    func largeValidSizeSucceeds() throws {
        let context = try makeContext()
        #expect(context.createGraphics(2048, 2048) != nil)
    }
}

// MARK: - createWindow の契約 (Issue #842)

/// `createWindow` の doc は「作成に失敗した場合は `nil`」。退化した
/// ``SketchWindowConfig`` でも、abort ではなくこの契約どおりに返ること。
///
/// 非ヘッドレスは `makeKeyAndOrderFront` で画面にウィンドウが出るため構築しない
/// (`SketchWindowHeadlessTests` と同じ方針)。
@Suite("createWindow の退化 config", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct DegenerateWindowConfigTests {

    private func makeContext() throws -> SketchContext {
        let shared = try SharedMetalResources()
        let renderer = try MetaphorRenderer(sharedResources: shared, width: 32, height: 32)
        let context = SketchContext(
            renderer: renderer,
            canvas: try Canvas2D(renderer: renderer),
            canvas3D: try Canvas3D(renderer: renderer),
            input: renderer.input
        )
        context._sharedResources = shared
        return context
    }

    @Test("退化した寸法では nil を返す", arguments: degenerateSizes)
    fileprivate func degenerateSizeReturnsNil(size: DegenerateSize) throws {
        let context = try makeContext()
        let config = SketchWindowConfig(width: size.width, height: size.height, title: "degenerate")
        #expect(context.createWindow(config, isHeadless: true) == nil)
    }

    @Test("上限を超える寸法では nil を返す", arguments: oversizedSizes)
    fileprivate func oversizedReturnsNil(size: DegenerateSize) throws {
        let context = try makeContext()
        let config = SketchWindowConfig(width: size.width, height: size.height, title: "oversized")
        #expect(context.createWindow(config, isHeadless: true) == nil)
    }

    /// `windowScale: 0` はキャンバス側の寸法が正常なのでテクスチャのガードには掛からず、
    /// 修正前は 0×0 pt の「見えないのに `isOpen == true`」なウィンドウが残っていた。
    @Test("windowScale が 0 以下なら nil を返す", arguments: [Float(0), -1, -0.5])
    func nonPositiveWindowScaleReturnsNil(scale: Float) throws {
        let context = try makeContext()
        let config = SketchWindowConfig(
            width: 64, height: 64, title: "scale", windowScale: scale
        )
        #expect(context.createWindow(config, isHeadless: true) == nil)
    }

    @Test("windowScale が 0 以下なら init は invalidParameter を投げる")
    func nonPositiveWindowScaleThrows() throws {
        let shared = try SharedMetalResources()
        #expect(throws: MetaphorError.self) {
            _ = try SketchWindow(
                config: SketchWindowConfig(
                    width: 64, height: 64, title: "scale-throw", windowScale: 0
                ),
                sharedResources: shared,
                isHeadless: true
            )
        }
    }

    /// ガードが効きすぎていないこと。1 未満でも正の倍率は正当な指定。
    @Test("正の windowScale はそのまま通る", arguments: [Float(0.25), 1, 2])
    func positiveWindowScaleSucceeds(scale: Float) throws {
        let context = try makeContext()
        defer { context.closeAllWindows() }

        let config = SketchWindowConfig(
            width: 64, height: 64, title: "scale-ok", windowScale: scale
        )
        #expect(context.createWindow(config, isHeadless: true) != nil)
    }
}
