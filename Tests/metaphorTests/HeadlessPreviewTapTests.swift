import AppKit
import Metal
import MetaphorTestSupport
import Testing

@testable import MetaphorCore

/// メニュー内プレビューの取り出し（``HeadlessPreviewTap``）を検証します。
///
/// 大きさの計算は純関数として、実際にフレームが取れることは実 GPU で確かめます。
@Suite("Headless preview")
@MainActor
struct HeadlessPreviewTapTests {

    // MARK: - 大きさの計算（純関数）

    @Test("thumbnail fits the box while keeping the aspect ratio")
    func thumbnailFits() {
        // 16:9 は横で頭打ち、4:3 は縦で頭打ち。
        let wide = HeadlessPreviewTap.thumbnailSize(width: 1920, height: 1080, box: (480, 360))
        #expect(wide == (480, 270))
        let tall = HeadlessPreviewTap.thumbnailSize(width: 1080, height: 1920, box: (480, 360))
        #expect(tall == (203, 360))
    }

    @Test("a small canvas is not blown up")
    func noUpscale() {
        // 拡大するとメニューの中でぼやけるだけなので、元より大きくしない。
        #expect(HeadlessPreviewTap.thumbnailSize(width: 64, height: 64, box: (480, 360)) == (64, 64))
    }

    @Test("degenerate sizes never produce a zero-sized texture")
    func degenerate() {
        // 0 を返すと makeTexture が失敗する。1px に丸める。
        #expect(HeadlessPreviewTap.thumbnailSize(width: 0, height: 100, box: (480, 360)) == (1, 1))
        #expect(HeadlessPreviewTap.thumbnailSize(width: 4000, height: 1, box: (480, 360)) == (480, 1))
    }

    @Test("preview view fits the image inside its box")
    func aspectFit() {
        let box = NSRect(x: 0, y: 0, width: 240, height: 180)
        // 16:9 の絵は上下に余白ができ、中央に置かれる。
        let fitted = HeadlessPreviewView.aspectFit(imageWidth: 1920, imageHeight: 1080, into: box)
        #expect(fitted.width == 240)
        #expect(fitted.height == 135)
        #expect(fitted.midX == box.midX)
        #expect(fitted.midY == box.midY)
    }

    // MARK: - 実 GPU での取り出し

    @Test(
        "a frame is captured only while the menu is open",
        .enabled(if: MTLCreateSystemDefaultDevice() != nil)
    )
    func capturesOnlyWhileOpen() throws {
        let renderer = try MetaphorRenderer(width: 320, height: 180)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
        renderer.onDraw = { encoder, _ in
            context.beginFrame(encoder: encoder, time: 0, deltaTime: 0)
            context.canvas.background(255, 0, 0)
            context.endFrame()
        }
        renderer.useExternalRenderLoop = true

        // 間引き（`minimumInterval`）が先に効いて「閉じているから撮らない」を隠さないよう、
        // 更新レートは十分速くしておく。
        let tap = HeadlessPreviewTap(box: (160, 160), fps: 1000)
        renderer.addPlugin(tap)

        // 1 枚目だけはメニューが閉じていても取る（`noLoop()` の作品はこの 1 枚しか
        // 描かないので、ここで取らないとメニューに永久に絵が出ない）。
        // 320×180 は 160×160 の箱に入れると 160×90。
        renderer.renderFrame()
        try drainGPU(renderer, until: { tap.latestFrame != nil })
        #expect(tap.captureCount == 1)
        let frame = try #require(tap.latestFrame)
        #expect(frame.width == 160)
        #expect(frame.height == 90)

        // 2 枚目以降は閉じている間は取らない（＝コストはゼロ）。
        Thread.sleep(forTimeInterval: 0.01)  // 間引きの窓を跨がせる
        renderer.renderFrame()
        renderer.renderFrame()
        try drainGPU(renderer)
        #expect(tap.captureCount == 1)

        // 開いている間は取り直す。
        tap.isCapturing = true
        Thread.sleep(forTimeInterval: 0.01)
        renderer.renderFrame()
        try drainGPU(renderer)
        #expect(tap.captureCount == 2)
        #expect(tap.latestFrame != nil)

        // 閉じたらまた止まる。
        tap.isCapturing = false
        Thread.sleep(forTimeInterval: 0.01)
        renderer.renderFrame()
        try drainGPU(renderer)
        #expect(tap.captureCount == 2)
    }

    /// 積んだコマンドバッファが完了しきるまで待ちます。
    ///
    /// 同じキューのバッファは積んだ順に完了するので、空のバッファを 1 本流して
    /// `waitUntilCompleted()` すれば、その前のフレームは完了しています。完了ハンドラは
    /// 別スレッドで走るため、その結果を見たいときだけ `until` で条件を渡し、**この
    /// スレッドを直接止めて**待ちます（`await` で待つと、CI の並列実行でメインアクターが
    /// 混んだときに待ち時間の見積もりが当てにならない — 実際にそれで落ちた）。
    private func drainGPU(
        _ renderer: MetaphorRenderer, until condition: () -> Bool = { true }
    ) throws {
        let commandBuffer = try #require(renderer.commandQueue.makeCommandBuffer())
        try MetalTestHelper.commit(commandBuffer)
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.002)
        }
    }
}
