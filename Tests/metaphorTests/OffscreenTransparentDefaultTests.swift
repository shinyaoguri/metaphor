import Metal
import MetaphorTestSupport
import Testing
import simd

@testable import MetaphorCore
@testable import metaphor

// MARK: - オフスクリーンの既定の下地（#914）

/// `createGraphics()` / `createGraphics3D()` は **透明で始まる**。
///
/// オフスクリーンは「層」として重ねるのが主用途なので、不透明な黒で始まると
/// `image()` の前景や `MergePass(.alpha)` に置いたときに下のものを覆ってしまう
/// （ADR-0012 の趣旨 — オフスクリーンを透明で始められる＝レイヤー合成の土台）。
///
/// 従来の不透明な黒が要るときは `background(0)` を 1 行呼ぶ。その移行手順が効くことも
/// ここで見張る。
///
/// 2D と 3D を同じスイートに並べているのは、**2 面の既定が揃っていること**が #830 から
/// 引き継いだ要件だから（3D だけ透明にすると新しい非対称が生まれる、というのが #830 で
/// 既定を変えなかった理由）。片方だけ直すとここが赤くなる。
@Suite("Offscreen transparent default (#914)", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct OffscreenTransparentDefaultTests {

    private static let size = 32

    private func makeGraphics() throws -> Graphics {
        try Graphics(
            device: MetalTestHelper.device!,
            commandQueue: try MetalTestHelper.commandQueue(),
            shaderLibrary: try MetalTestHelper.shaderLibrary(),
            depthStencilCache: try MetalTestHelper.depthStencilCache(),
            width: Self.size,
            height: Self.size
        )
    }

    private func makeGraphics3D() throws -> Graphics3D {
        try Graphics3D(
            device: MetalTestHelper.device!,
            commandQueue: try MetalTestHelper.commandQueue(),
            shaderLibrary: try MetalTestHelper.shaderLibrary(),
            depthStencilCache: try MetalTestHelper.depthStencilCache(),
            width: Self.size,
            height: Self.size
        )
    }

    /// 画素を 0...255 の整数で読む（公開 API 側なので straight alpha。ADR-0012）。
    private func pixel(_ image: MImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        image.loadPixels()
        let c = image.get(x, y)
        func q(_ v: Float) -> Int { Int((v * 255).rounded()) }
        return (q(c.r), q(c.g), q(c.b), q(c.a))
    }

    // MARK: - 既定の下地

    @Test("a fresh Graphics starts out transparent")
    func graphicsStartsTransparent() throws {
        let pg = try makeGraphics()
        pg.beginDraw()
        pg.endDraw(wait: true)

        let got = pixel(pg.toImage(), Self.size / 2, Self.size / 2)
        #expect(got == (0, 0, 0, 0), "background() を呼ばない Graphics は透明で始まる (got \(got))")
    }

    @Test("a fresh Graphics3D starts out transparent")
    func graphics3DStartsTransparent() throws {
        let pg3d = try makeGraphics3D()
        pg3d.beginDraw()
        pg3d.endDraw(wait: true)

        let got = pixel(pg3d.toImage(), Self.size / 2, Self.size / 2)
        #expect(got == (0, 0, 0, 0), "background() を呼ばない Graphics3D は透明で始まる (got \(got))")
    }

    /// 描いた領域だけが不透明になり、その外は透明のまま残る（= 層として使える）。
    @Test("only what is drawn becomes opaque")
    func drawnAreaIsOpaqueAndTheRestStaysTransparent() throws {
        let pg = try makeGraphics()
        pg.beginDraw()
        pg.noStroke()
        pg.fill(Color(r: 1, g: 0, b: 0))
        pg.rect(0, 0, Float(Self.size) / 2, Float(Self.size))
        pg.endDraw(wait: true)

        let image = pg.toImage()
        let inside = pixel(image, Self.size / 4, Self.size / 2)
        let outside = pixel(image, Self.size * 3 / 4, Self.size / 2)
        #expect(inside == (255, 0, 0, 255), "塗った側は不透明 (got \(inside))")
        #expect(outside == (0, 0, 0, 0), "塗っていない側は透明のまま (got \(outside))")
    }

    // MARK: - 移行手順（従来の不透明な黒に戻す）

    @Test("background(0) restores the opaque black backdrop")
    func explicitBackgroundRestoresOpaqueBlack() throws {
        let pg = try makeGraphics()
        pg.beginDraw()
        pg.background(0)
        pg.endDraw(wait: true)

        let got = pixel(pg.toImage(), Self.size / 2, Self.size / 2)
        #expect(got == (0, 0, 0, 255), "background(0) は従来どおり不透明な黒 (got \(got))")
    }

    @Test("Graphics3D background(0) restores the opaque black backdrop")
    func explicitBackground3DRestoresOpaqueBlack() throws {
        let pg3d = try makeGraphics3D()
        pg3d.beginDraw()
        pg3d.background(0)
        pg3d.endDraw(wait: true)

        let got = pixel(pg3d.toImage(), Self.size / 2, Self.size / 2)
        #expect(got == (0, 0, 0, 255), "background(0) は従来どおり不透明な黒 (got \(got))")
    }

    // MARK: - メインキャンバスへ重ねたとき

    /// 空のオフスクリーンを貼っても下地が残る。既定が不透明な黒だった頃は、
    /// ここが黒い矩形で塗り潰されていた。
    @Test("an untouched offscreen layer does not cover the main canvas", arguments: [false, true])
    func emptyLayerKeepsTheBackdrop(threeD: Bool) throws {
        let fb = try OffscreenSketchHarness.render(size: 64) { ctx in
            ctx.background(Color(r: 1, g: 0, b: 0))
            if threeD {
                guard let pg3d = ctx.createGraphics3D(32, 32) else { return }
                pg3d.beginDraw()
                pg3d.endDraw()
                ctx.image(pg3d, 0, 0)
            } else {
                guard let pg = ctx.createGraphics(32, 32) else { return }
                pg.beginDraw()
                pg.endDraw()
                ctx.image(pg, 0, 0)
            }
        }

        let i = (16 * fb.width + 16) * 4
        let got = (Int(fb.rgba[i]), Int(fb.rgba[i + 1]), Int(fb.rgba[i + 2]))
        #expect(
            got == (255, 0, 0),
            "空の\(threeD ? "3D " : "")オフスクリーンが下地を覆っている (got \(got))")
    }

    /// メインキャンバスの既定は据え置き（不透明な黒）。オフスクリーンだけを変えた、
    /// という判断（#914）をここで固定する。
    @Test("the main canvas still starts opaque")
    func mainCanvasStaysOpaque() throws {
        let fb = try OffscreenSketchHarness.render(size: 16) { _ in }
        let i = (8 * fb.width + 8) * 4
        let got = (Int(fb.rgba[i]), Int(fb.rgba[i + 1]), Int(fb.rgba[i + 2]), Int(fb.rgba[i + 3]))
        #expect(got == (0, 0, 0, 255), "メインキャンバスの既定は不透明な黒のまま (got \(got))")
    }
}
