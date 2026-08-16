import Testing
import Metal
@testable import metaphor
@testable import MetaphorCore
import MetaphorTestSupport

/// メインキャンバス loadPixels() の readback（Processing 互換、#202 / #326）。
///
/// #202 は「前フレーム末尾までに確定した内容」を読む readback を入れた。#326 では
/// `draw()` の途中で呼ばれた場合に**そのフレームのそこまでの描画**を読む
/// （= Processing の意味論）ようメインパスを分割する経路を足している。
@Suite("Canvas loadPixels Readback", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct CanvasPixelsTests {

    /// 実スケッチ（`SketchRunner`）と同じ結線でオフスクリーンを回すハーネス。
    ///
    /// - Parameter shadows: true なら影オン経路（記録 → shadow → 再生）を通す。
    ///   この経路では `draw()` が記録パスとして先に走るため、同一フレーム読み戻しは
    ///   使えず前フレーム内容へフォールバックする（#326 の既知の制限）。
    private func makeHarness(
        size: Int = 64,
        shadows: Bool = false,
        draw: @escaping (SketchContext) -> Void
    ) throws -> (MetaphorRenderer, SketchContext) {
        let renderer = try MetaphorRenderer(width: size, height: size)
        let canvas = try Canvas2D(renderer: renderer)
        let canvas3D = try Canvas3D(renderer: renderer)
        let context = SketchContext(
            renderer: renderer, canvas: canvas, canvas3D: canvas3D, input: renderer.input
        )
        canvas.onSetClearColor = { [weak renderer] r, g, b, a in
            renderer?.setClearColor(r, g, b, a)
        }
        renderer.useExternalRenderLoop = true
        renderer.onDraw = { encoder, time in
            context.beginFrame(encoder: encoder, time: Float(time), deltaTime: 0)
            draw(context)
            context.endFrame()
        }
        if shadows {
            renderer.onAfterDraw = { commandBuffer in
                context.canvas3D.performShadowPass(commandBuffer: commandBuffer)
            }
            renderer.shadowDeferActive = { context.canvas3D.shouldRecordMainPass }
            renderer.onRecordFrame = { time in
                context.beginRecordingFrame(time: Float(time), deltaTime: 0)
                draw(context)
                context.endRecordingFrame()
            }
            renderer.onReplayMain = { encoder, time in
                context.replayDeferredMain(encoder: encoder, time: Float(time))
            }
            context.enableShadows(resolution: 256)
        }
        return (renderer, context)
    }

    /// フレームバッファ全体を読み戻す（ゴールデン回帰基盤の比較ヘルパーを流用、#330）。
    private func framebuffer(_ renderer: MetaphorRenderer) throws -> GoldenImage {
        try GoldenImage.readback(
            texture: renderer.textureManager.colorTexture,
            commandQueue: renderer.commandQueue
        )
    }

    private func channels(_ packed: UInt32) -> (r: UInt32, g: UInt32, b: UInt32, a: UInt32) {
        ((packed >> 16) & 0xFF, (packed >> 8) & 0xFF, packed & 0xFF, (packed >> 24) & 0xFF)
    }

    // MARK: - 同一フレーム読み戻し（#326 の本題）

    /// Processing の `loadPixels()` は「呼び出し時点の描画結果」を返す。
    /// #205 時点の実装は前フレーム内容しか返せず、この検証は落ちる。
    @Test("draw() 途中の loadPixels は同一フレームのそこまでの描画を読む")
    func loadPixelsReadsSameFrameDrawing() throws {
        var insideShape: UInt32 = 0
        var outsideShape: UInt32 = 0
        let (renderer, _) = try makeHarness { c in
            c.background(Color(r: 0, g: 0, b: 0))
            c.noStroke()
            c.fill(Color(r: 1, g: 0, b: 0))
            c.rect(0, 0, 32, 64)          // 左半分だけ赤
            c.loadPixels()                // ← ここまでの描画が読めること
            if let pb = c.pixelBuffer {
                insideShape = pb.pixels[32 * 64 + 8]    // 矩形の内側
                outsideShape = pb.pixels[32 * 64 + 56]  // 矩形の外側
            }
        }
        renderer.renderFrame()

        let inside = channels(insideShape)
        let outside = channels(outsideShape)
        #expect(inside.r > 200 && inside.g < 50 && inside.b < 50,
                "同一フレームで描いた矩形が読めるべき: \(String(insideShape, radix: 16))")
        #expect(outside.r < 50 && outside.g < 50 && outside.b < 50,
                "矩形の外は background の黒: \(String(outsideShape, radix: 16))")
    }

    /// 「読み戻し → 加工 → 描き戻し」が**同じ draw() の中で**完結すること。
    @Test("同一フレームの loadPixels → 反転 → updatePixels が最終フレームに反映される")
    func sameFrameRoundTripAppliesToFramebuffer() throws {
        let (renderer, _) = try makeHarness { c in
            c.background(Color(r: 0, g: 0, b: 0))
            c.noStroke()
            c.fill(Color(r: 1, g: 0, b: 0))
            c.rect(0, 0, 32, 64)          // 左半分だけ赤
            c.loadPixels()
            if let pb = c.pixelBuffer {
                // RGB のみ反転（アルファは保つ）: 赤 → シアン、黒 → 白
                for i in 0..<pb.pixels.count {
                    pb.pixels[i] ^= 0x00FF_FFFF
                }
            }
            c.updatePixels()
        }
        renderer.renderFrame()

        let image = try framebuffer(renderer)
        func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * image.width + x) * 4
            return (Int(image.rgba[i]), Int(image.rgba[i + 1]), Int(image.rgba[i + 2]))
        }
        let left = rgb(8, 32)
        let right = rgb(56, 32)
        #expect(left.0 < 50 && left.1 > 200 && left.2 > 200,
                "赤の反転（シアン）が描き戻されるべき: \(left)")
        #expect(right.0 > 200 && right.1 > 200 && right.2 > 200,
                "黒の反転（白）が描き戻されるべき: \(right)")
    }

    /// 読み戻しのためのパス分割が**見た目を変えない**こと。
    ///
    /// 分割は「エンコーダを閉じて別コマンドバッファで継続する」だけなので、
    /// 同じシーンなら 1 ビットも変わってはならない。継続パスの loadAction を
    /// `.clear` にする等の取り違えはここで落ちる。
    @Test("loadPixels を挟んでもフレームの描画結果は 1 ビットも変わらない")
    func splitDoesNotChangeRenderedOutput() throws {
        func renderScene(callingLoadPixels: Bool) throws -> GoldenImage {
            let (renderer, _) = try makeHarness { c in
                c.background(Color(r: 0.08, g: 0.09, b: 0.12))
                c.noStroke()
                c.fill(Color(r: 0.90, g: 0.30, b: 0.25))
                c.rect(6, 6, 24, 20)
                c.fill(Color(r: 0.20, g: 0.70, b: 0.90))
                c.circle(44, 20, 22)
                if callingLoadPixels { c.loadPixels() }   // ← 分割点
                c.fill(Color(r: 0.95, g: 0.80, b: 0.20))
                c.triangle(10, 58, 32, 32, 54, 58)
                c.stroke(Color(r: 1, g: 1, b: 1))
                c.strokeWeight(2)
                c.line(2, 48, 62, 48)
            }
            renderer.renderFrame()
            return try framebuffer(renderer)
        }

        let plain = try renderScene(callingLoadPixels: false)
        let split = try renderScene(callingLoadPixels: true)
        let diff = plain.compare(to: split)
        #expect(diff.isIdentical, "loadPixels のパス分割で描画結果が変わった: \(diff.summary)")
    }

    /// 分割後も 2D の状態（変換・スタイル・クリップ）が引き継がれること。
    @Test("分割後も変換・スタイル・クリップが維持される")
    func stateSurvivesTheSplit() throws {
        var afterSplit: UInt32 = 0
        var clippedOut: UInt32 = 0
        let (renderer, ctx) = try makeHarness { c in
            c.background(Color(r: 0, g: 0, b: 0))
            c.noStroke()
            c.fill(Color(r: 0, g: 1, b: 0))     // 緑を「分割前に」設定
            c.pushMatrix()
            c.translate(32, 0)                   // 変換も分割前に設定
            c.beginClip(32, 0, 32, 32)           // 上半分だけ通すクリップ
            c.loadPixels()                       // ← 分割点
            c.rect(0, 0, 32, 64)                 // translate 後なので x=32..64
            c.endClip()
            c.popMatrix()
        }
        renderer.renderFrame()

        ctx.loadPixels()
        let pb = try #require(ctx.pixelBuffer)
        afterSplit = pb.pixels[16 * 64 + 48]     // クリップ内・矩形内
        clippedOut = pb.pixels[48 * 64 + 48]     // クリップ外（矩形は描かれない）
        let kept = channels(afterSplit)
        let cut = channels(clippedOut)
        #expect(kept.g > 200 && kept.r < 50,
                "分割後も fill/translate が効いた矩形が描かれる: \(String(afterSplit, radix: 16))")
        #expect(cut.g < 50,
                "分割後もクリップが効いている: \(String(clippedOut, radix: 16))")
    }

    // MARK: - フレーム外・影オン経路（コミット済みフレームへのフォールバック）

    @Test("フレーム外の loadPixels は直近にコミット済みのキャンバス内容を読む")
    func loadPixelsReadsCanvas() throws {
        let (renderer, ctx) = try makeHarness { c in
            c.background(Color(r: 1, g: 0, b: 0))   // 赤で塗る
        }
        renderer.renderFrame()

        // フレーム確定後の loadPixels は描画内容（赤）を読み戻す
        // （#205 より前の実装は空のバッファを作るだけで、常に 0 が読めていた）
        ctx.loadPixels()
        let pb = try #require(ctx.pixelBuffer)
        let center = channels(pb.pixels[32 * 64 + 32])
        #expect(center.r > 200 && center.g < 50,
                "loadPixels はキャンバスの赤を読み戻すべき: \(center)")
    }

    @Test("loadPixels then updatePixels round-trips content (feedback pattern)")
    func loadModifyUpdateRoundTrip() throws {
        var frameIndex = 0
        let (renderer, ctx) = try makeHarness { c in
            if frameIndex == 0 {
                // フレーム 1: 緑で塗る
                c.background(Color(r: 0, g: 1, b: 0))
            } else {
                // フレーム 2: 前フレームの内容を読み、左半分を青へ加工して描き戻す
                c.loadPixels()
                if let pb = c.pixelBuffer {
                    for y in 0..<64 {
                        for x in 0..<32 {
                            pb.pixels[y * 64 + x] = 0xFF00_00FF  // 青
                        }
                    }
                }
                c.updatePixels()
            }
            frameIndex += 1
        }
        renderer.renderFrame()   // フレーム 1: 緑
        renderer.renderFrame()   // フレーム 2: 読み戻し + 加工 + 描き戻し

        ctx.loadPixels()
        let pb = try #require(ctx.pixelBuffer)
        let left = channels(pb.pixels[32 * 64 + 8])     // 加工した左半分 → 青
        let right = channels(pb.pixels[32 * 64 + 56])   // 未加工の右半分 → 緑が保持される
        #expect(left.b > 200 && left.g < 50, "左半分は加工後の青: \(left)")
        #expect(right.g > 200, "右半分は読み戻された緑が保持される: \(right)")
    }

    /// 影オン経路では `draw()` が記録パスとして先に走るため分割できない。
    /// 同一フレームではなく**直前のコミット済みフレーム**が読めることを固定する
    /// （黙って壊れるのではなく、定義された挙動であることの保証）。
    @Test("影オン経路の loadPixels は前フレーム内容へフォールバックする")
    func shadowPathFallsBackToPreviousFrame() throws {
        var frameIndex = 0
        var readDuringDraw: UInt32 = 0
        let (renderer, _) = try makeHarness(shadows: true) { c in
            if frameIndex == 0 {
                c.background(Color(r: 1, g: 0, b: 0))       // フレーム 1: 赤
            } else {
                c.background(Color(r: 0, g: 0, b: 1))       // フレーム 2: 青
                c.loadPixels()
                if let pb = c.pixelBuffer {
                    // 3D の箱がかからない隅を読む（背景色だけで判別する）。
                    readDuringDraw = pb.pixels[4 * 64 + 4]
                }
            }
            // 影経路（記録 → shadow → 再生）へ入るための 3D 要素。
            c.fill(Color(r: 1, g: 1, b: 1))
            c.pushMatrix()
            c.translate(32, 32, 0)
            c.box(8)
            c.popMatrix()
            frameIndex += 1
        }
        renderer.renderFrame()
        renderer.renderFrame()

        let read = channels(readDuringDraw)
        #expect(read.r > 200 && read.b < 50,
                "影オン経路では前フレーム（赤）が読める。分割できたなら青になる: \(read)")
    }

    // MARK: - リサイズ・失敗系

    @Test("loadPixels recreates the buffer when the canvas is resized")
    func loadPixelsResize() throws {
        let (renderer, ctx) = try makeHarness { c in
            c.background(Color(r: 0, g: 0, b: 1))
        }
        renderer.renderFrame()
        ctx.loadPixels()
        #expect(ctx.pixelBuffer?.width == 64)

        renderer.resizeCanvas(width: 32, height: 32)
        ctx.rebuildCanvas(
            canvas: try Canvas2D(renderer: renderer),
            canvas3D: try Canvas3D(renderer: renderer)
        )
        ctx.loadPixels()
        #expect(ctx.pixelBuffer?.width == 32, "リサイズ後はバッファが作り直される")
    }

    @Test("サイズ 0 のピクセルバッファは生成されない")
    func zeroSizedPixelBufferIsRejected() throws {
        let device = try #require(MetalTestHelper.device)
        #expect(PixelBuffer(width: 0, height: 8, device: device) == nil)
        #expect(PixelBuffer(width: 8, height: 0, device: device) == nil)
        #expect(PixelBuffer(width: -4, height: 8, device: device) == nil)
    }

    @Test("loadPixels 前の pixels は空、updatePixels は no-op（クラッシュしない）")
    func updateBeforeLoadIsNoOp() throws {
        var pixelCountDuringDraw = -1
        let (renderer, ctx) = try makeHarness { c in
            c.background(Color(r: 0, g: 1, b: 0))
            c.updatePixels()          // loadPixels 前 → 何もしない
            pixelCountDuringDraw = c.pixelBuffer?.pixels.count ?? 0
        }
        renderer.renderFrame()

        #expect(ctx.pixelBuffer == nil, "loadPixels を呼ばなければバッファは確保されない（遅延確保）")
        #expect(pixelCountDuringDraw == 0)

        // updatePixels が no-op なら、キャンバスは background の緑のまま。
        let image = try framebuffer(renderer)
        let i = (32 * image.width + 32) * 4
        #expect(Int(image.rgba[i + 1]) > 200 && Int(image.rgba[i]) < 50,
                "updatePixels の no-op がキャンバスを壊していないこと")
    }

    // MARK: - pixels は straight alpha（ADR-0012 / #848）

    /// 半透明を作るのに使う色。premultiplied で格納されると `× 0.5` された値になる。
    private static let translucent = Color(r: 0.2, g: 0.8, b: 0.4, alpha: 0.5)

    /// キャンバスに半透明の画素を敷いたフレームを 1 枚回す。
    ///
    /// `background(α<1)` ではなく `.opaque` の `rect()` で作る（`background()` は
    /// 置き換えの意味論を持つ別の経路で、ここで見たいのは `pixels` の境界だから）。
    private func harnessWithTranslucentCanvas(
        after: @escaping (SketchContext) -> Void
    ) throws -> (MetaphorRenderer, SketchContext) {
        try makeHarness { c in
            c.blendMode(.opaque)
            c.noStroke()
            c.fill(Self.translucent)
            c.rect(0, 0, 64, 64)
            after(c)
        }
    }

    /// `loadPixels()` が返すのは straight alpha（= 利用者が `fill()` で指定した値）。
    ///
    /// キャンバスの中身は premultiplied（ADR-0012）なので、blit で写しただけでは
    /// `α` が掛かった値が見える。`color(r, g, b, a)` は straight を詰める helper なので、
    /// 割り戻さないと**読む側と書く側で世界が食い違う**（#848）。
    @Test("loadPixels returns straight alpha, not premultiplied")
    func loadPixelsReturnsStraightAlpha() throws {
        var got: (r: UInt32, g: UInt32, b: UInt32, a: UInt32) = (0, 0, 0, 0)
        let (renderer, _) = try harnessWithTranslucentCanvas { c in
            c.loadPixels()
            if let pb = c.pixelBuffer {
                got = self.channels(pb.pixels[32 * 64 + 32])
            }
        }
        renderer.renderFrame()

        // fill(0.2, 0.8, 0.4, 0.5) = (51, 204, 102, 128)。premultiplied なら (26, 102, 51, 128)
        #expect(abs(Int(got.r) - 51) <= 2 && abs(Int(got.g) - 204) <= 2
                && abs(Int(got.b) - 102) <= 2 && abs(Int(got.a) - 128) <= 2,
                "loadPixels が premultiplied のまま返している: \(got) — #848")
    }

    /// `color()` で作った straight な半透明画素が、`fill()` と同じように合成される。
    ///
    /// `updatePixels()` はフルスクリーンクワッドを描くので、テクスチャの中身が
    /// straight であることを描画側にも伝えないと、**α を掛けずに over される**（明るく出る）。
    @Test("a straight translucent pixel written into pixels composites like fill()")
    func updatePixelsCompositesStraightAlpha() throws {
        let (renderer, _) = try makeHarness { c in
            c.blendMode(.opaque)
            c.noStroke()
            c.fill(Color(r: 1, g: 1, b: 1))       // 不透明な白の下地
            c.rect(0, 0, 64, 64)
            c.loadPixels()
            if let pb = c.pixelBuffer {
                for i in 0..<pb.pixels.count {
                    pb.pixels[i] = color(102, 102, 102, 128)   // straight な半透明グレー
                }
            }
            c.blendMode(.alpha)
            c.updatePixels()
        }
        renderer.renderFrame()

        let image = try framebuffer(renderer)
        let i = (32 * image.width + 32) * 4
        let r = Int(image.rgba[i])
        // 0.4 * 0.502 + 1.0 * (1 - 0.502) = 0.699 → 178。α を掛けずに over すると 229
        #expect(abs(r - 178) <= 2,
                "straight な pixels が α を掛けずに合成されている: \(r) — #848")
    }

    /// 読んだ値をそのまま書き戻したら、キャンバスは変わらない（`set(x, y, get(x, y))` が恒等）。
    ///
    /// 読む側だけ・書く側だけを直すとここが落ちる（境界は 2 つで 1 組）。
    @Test("loadPixels then updatePixels leaves a translucent canvas unchanged")
    func pixelRoundTripIsIdentityOnTheCanvas() throws {
        func render(withRoundTrip: Bool) throws -> GoldenImage {
            let (renderer, _) = try harnessWithTranslucentCanvas { c in
                guard withRoundTrip else { return }
                c.loadPixels()
                c.updatePixels()   // 加工せずそのまま描き戻す
            }
            renderer.renderFrame()
            return try self.framebuffer(renderer)
        }

        let baseline = try render(withRoundTrip: false)
        let roundTripped = try render(withRoundTrip: true)
        let i = (32 * baseline.width + 32) * 4
        let want = (baseline.rgba[i], baseline.rgba[i + 1], baseline.rgba[i + 2], baseline.rgba[i + 3])
        let got = (roundTripped.rgba[i], roundTripped.rgba[i + 1],
                   roundTripped.rgba[i + 2], roundTripped.rgba[i + 3])
        #expect(abs(Int(got.0) - Int(want.0)) <= 1 && abs(Int(got.1) - Int(want.1)) <= 1
                && abs(Int(got.2) - Int(want.2)) <= 1 && abs(Int(got.3) - Int(want.3)) <= 1,
                "pixels の往復が恒等でない: \(want) → \(got) — #848")
    }

    @Test("寸法が合わないテクスチャからの読み戻しはエンコードされない")
    func downloadRejectsMismatchedSource() throws {
        let device = try #require(MetalTestHelper.device)
        let pb = try #require(PixelBuffer(width: 16, height: 16, device: device))
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 8, height: 8, mipmapped: false
        )
        desc.usage = [.shaderRead, .renderTarget]
        let mismatched = try #require(device.makeTexture(descriptor: desc))
        let queue = try #require(device.makeCommandQueue())
        let cb = try #require(queue.makeCommandBuffer())
        #expect(pb.encodeDownload(from: mismatched, into: cb) == false)
    }
}
