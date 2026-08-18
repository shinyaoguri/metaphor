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

    /// 2D と 3D が重なるシーンでも、分割が**見た目を変えない**こと（#832）。
    ///
    /// 上の `splitDoesNotChangeRenderedOutput` は 2D だけのシーンなので、
    /// **2D と 3D をどちらの順で吐くか**という食い違いは原理的に検出できない。
    /// フレーム末尾 `SketchContext.endFrame()` は `canvas3D.end()` → `canvas.end()`
    /// の順（= 2D が 3D の手前）で吐くので、分割点も同じ順でなければならない。
    /// 逆順（2D → 3D）で吐くと、分割前に描いた 2D が箱の背後へ落ちる。
    @Test("2D/3D が重なるシーンでも loadPixels の分割で描画結果が変わらない")
    func splitPreserves2DOver3DCompositing() throws {
        func renderScene(callingLoadPixels: Bool) throws -> GoldenImage {
            let (renderer, _) = try makeHarness { c in
                c.background(Color(r: 0.05, g: 0.05, b: 0.08))
                c.lights()
                c.noStroke()
                // 3D: 画面中央を覆う青い箱
                c.fill(Color(r: 0.15, g: 0.35, b: 0.95))
                c.pushMatrix()
                c.translate(32, 32, 0)
                c.box(28)
                c.popMatrix()
                // 2D: 箱に重なる黄色い帯。呼び出し順で箱の後なので手前に出るべき
                c.fill(Color(r: 1.0, g: 0.85, b: 0.10))
                c.rect(4, 28, 56, 8)
                // ← 分割点。ここから先は何も描かないので、分割は「見た目に対して透明」
                //    でなければならない
                if callingLoadPixels { c.loadPixels() }
            }
            renderer.renderFrame()
            return try framebuffer(renderer)
        }

        let plain = try renderScene(callingLoadPixels: false)
        let split = try renderScene(callingLoadPixels: true)

        // 前提の確認: そもそも帯が箱の手前に出ていること（この足場が崩れると
        // 下の比較が「どちらも同じように壊れている」で通ってしまう）
        func rgb(_ image: GoldenImage, _ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * image.width + x) * 4
            return (Int(image.rgba[i]), Int(image.rgba[i + 1]), Int(image.rgba[i + 2]))
        }
        let overlapBaseline = rgb(plain, 32, 32)
        #expect(overlapBaseline.0 > 150 && overlapBaseline.2 < 120,
                "前提が崩れている: 分割なしでも帯が箱の手前に出ていない: \(overlapBaseline)")

        let overlapSplit = rgb(split, 32, 32)
        #expect(overlapSplit.0 > 150 && overlapSplit.2 < 120,
                "loadPixels の分割で 2D の帯が 3D の箱の背後へ落ちた: \(overlapSplit) — #832")

        let diff = plain.compare(to: split)
        #expect(diff.isIdentical, "loadPixels のパス分割で描画結果が変わった: \(diff.summary) — #832")
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

    /// `updatePixels()` はピクセルグリッドに 1:1 で貼る（半ピクセルずれない）。
    ///
    /// 2D の投影行列は整数座標をピクセル中心へ寄せるため半ピクセルずらしてある
    /// （`strokeWeight(1)` をクリスプに出すため）。フルスクリーンクワッドを素直に
    /// `x: 0, w: width` で張ると、各フラグメントがテクセルの境目をサンプルし
    /// `filter::linear` が隣接 4 テクセルを 25% ずつ混ぜてしまう。全画素を一様に
    /// 加工する検証では気付けず、**1 画素だけ書き換えたときに初めて露見する**
    /// （`set()` が 4 画素へ散る・フィードバックがフレームごとに滲む。#812）。
    @Test("updatePixels は 1 画素の書き換えを滲ませずそのまま貼る")
    func updatePixelsIsPixelExact() throws {
        let (renderer, _) = try makeHarness { c in
            c.background(Color(r: 0, g: 0, b: 0))
            c.loadPixels()
            if let pb = c.pixelBuffer {
                pb.pixels[20 * 64 + 10] = color(255, 0, 0)   // 1 画素だけ赤
            }
            c.updatePixels()
        }
        renderer.renderFrame()

        let image = try framebuffer(renderer)
        func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * image.width + x) * 4
            return (Int(image.rgba[i]), Int(image.rgba[i + 1]), Int(image.rgba[i + 2]))
        }
        let hit = rgb(10, 20)
        #expect(hit.0 > 250 && hit.1 < 5 && hit.2 < 5,
                "書き換えた画素は満額の赤で出るべき（半ピクセルずれると 25% に落ちる）: \(hit)")
        for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1)] {
            let neighbour = rgb(10 + dx, 20 + dy)
            #expect(neighbour.0 < 5,
                    "隣接画素 (\(dx), \(dy)) へ滲んでいる: \(neighbour) — #812")
        }
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

// MARK: - キャンバスの get() / set()（#812）

/// キャンバス 1 画素の読み書き `get(x, y)` / `get(x, y, w, h)` / `set(x, y, c)`（#812）。
///
/// 設計上の要点は「**暗黙の読み戻しをしない**」こと。`loadPixels()` を呼んでいなければ
/// `get()` は黒を返し `set()` は no-op になる（`updatePixels()` と同じ流儀・ADR-0005）。
/// 暗黙に読み戻すと 1 画素ごとに GPU 待ち + レンダーパス分割が走り、絵そのものが変わる。
@Suite("Canvas get/set", .enabled(if: MetalTestHelper.isGPUAvailable))
@MainActor
struct CanvasGetSetTests {

    private static let size = 64

    /// `CanvasPixelsTests` と同じ結線のオフスクリーンハーネス（影なし経路）。
    private func makeHarness(
        draw: @escaping (SketchContext) -> Void
    ) throws -> (MetaphorRenderer, SketchContext) {
        let renderer = try MetaphorRenderer(width: Self.size, height: Self.size)
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
        return (renderer, context)
    }

    private func framebuffer(_ renderer: MetaphorRenderer) throws -> GoldenImage {
        try GoldenImage.readback(
            texture: renderer.textureManager.colorTexture,
            commandQueue: renderer.commandQueue
        )
    }

    private func close(_ got: Color, _ want: Color, tolerance: Float = 3.0 / 255.0) -> Bool {
        abs(got.r - want.r) <= tolerance && abs(got.g - want.g) <= tolerance
            && abs(got.b - want.b) <= tolerance && abs(got.a - want.a) <= tolerance
    }

    // MARK: - 失敗系: loadPixels() 前（ADR-0005 / #356 の約束）

    /// `loadPixels()` を呼ばずに `get()` / `set()` を叩いてもクラッシュせず、
    /// **暗黙の読み戻しも起きない**（= `set()` は絵を変えない）。
    @Test("loadPixels 前の get は黒、set は no-op（クラッシュも暗黙 readback もしない）")
    func getAndSetBeforeLoadPixels() throws {
        var gotBeforeLoad = Color.white
        var bufferExistedDuringDraw = true
        let (renderer, ctx) = try makeHarness { c in
            c.background(Color(r: 0, g: 1, b: 0))
            c.set(32, 32, Color(r: 1, g: 0, b: 0))   // loadPixels 前 → 何もしない
            gotBeforeLoad = c.get(32, 32)            // loadPixels 前 → 黒
            bufferExistedDuringDraw = c.pixelBuffer != nil
        }
        renderer.renderFrame()

        #expect(gotBeforeLoad == .black, "loadPixels 前の get は黒を返すべき: \(gotBeforeLoad)")
        #expect(bufferExistedDuringDraw == false,
                "get / set が暗黙に readback していない（バッファは遅延確保のまま）")
        #expect(ctx.pixelBuffer == nil, "フレーム後も readback は起きていない")

        // set が no-op なら、キャンバスは background の緑のまま。
        let image = try framebuffer(renderer)
        let i = (32 * image.width + 32) * 4
        #expect(Int(image.rgba[i + 1]) > 200 && Int(image.rgba[i]) < 50,
                "loadPixels 前の set がキャンバスを塗ってしまっている")
    }

    /// 矩形版も同じ約束: `loadPixels()` 前は nil（クラッシュしない）。
    @Test("loadPixels 前の矩形 get は nil")
    func rectGetBeforeLoadPixels() throws {
        var rect: MImage?
        let (renderer, _) = try makeHarness { c in
            c.background(Color(r: 0, g: 0, b: 0))
            rect = c.get(0, 0, 8, 8)
        }
        renderer.renderFrame()
        #expect(rect == nil)
    }

    /// 幅・高さが 0 以下の矩形は入口で弾く。
    @Test("サイズ 0 以下の矩形 get は nil")
    func rectGetRejectsNonPositiveSize() throws {
        var zeroWidth: MImage?
        var negativeHeight: MImage?
        let (renderer, _) = try makeHarness { c in
            c.background(Color(r: 0, g: 0, b: 0))
            c.loadPixels()
            zeroWidth = c.get(0, 0, 0, 8)
            negativeHeight = c.get(0, 0, 8, -4)
        }
        renderer.renderFrame()
        #expect(zeroWidth == nil)
        #expect(negativeHeight == nil)
    }

    // MARK: - 正常系

    /// `loadPixels()` 済みなら、描いた色がそのまま読める。
    ///
    /// 円は**わざと中心から外して**置く。中心対称なシーンだと `get` の x / y を
    /// 取り違えていても同じ色が読めてしまい、検査が素通りする。
    @Test("get は描いた色を返す（円の内側と外側）")
    func getReadsDrawnColors() throws {
        var center = Color.black
        var mirrored = Color.black
        var corner = Color.white
        let (renderer, _) = try makeHarness { c in
            c.background(Color(r: 0, g: 0, b: 1))     // 青の下地
            c.noStroke()
            c.fill(Color(r: 1, g: 0, b: 0))           // 赤い円（中心を外す）
            c.circle(20, 44, 20)
            c.loadPixels()
            center = c.get(20, 44)                    // 円の内側 → 赤
            mirrored = c.get(44, 20)                  // x/y を入れ替えた位置 → 青
            corner = c.get(2, 2)                      // 円の外側 → 青
        }
        renderer.renderFrame()

        #expect(self.close(center, Color(r: 1, g: 0, b: 0)),
                "円の中心は赤が読めるべき: \(center)")
        #expect(self.close(mirrored, Color(r: 0, g: 0, b: 1)),
                "x/y を取り違えている（(44, 20) は円の外): \(mirrored)")
        #expect(self.close(corner, Color(r: 0, g: 0, b: 1)),
                "円の外は background の青が読めるべき: \(corner)")
    }

    /// 範囲外の座標は黒（読み取り系はクラッシュしない・ADR-0005）。
    @Test("範囲外の get は黒")
    func getOutOfRangeReturnsBlack() throws {
        var results: [Color] = []
        let (renderer, _) = try makeHarness { c in
            c.background(Color(r: 1, g: 1, b: 1))
            c.loadPixels()
            results = [
                c.get(-1, -1),
                c.get(-1, 0),
                c.get(0, -1),
                c.get(Self.size, 0),
                c.get(0, Self.size),
            ]
        }
        renderer.renderFrame()

        #expect(results.count == 5)
        for (i, got) in results.enumerated() {
            #expect(got == .black, "範囲外 [\(i)] は黒であるべき: \(got)")
        }
    }

    /// 範囲外への `set()` は隣接画素を汚さない（インデックス計算の折り返し事故の検出）。
    @Test("範囲外の set は隣接画素を汚さない")
    func setOutOfRangeDoesNotTouchNeighbours() throws {
        var firstOfRow1 = Color.black
        var lastOfRow0 = Color.black
        var firstPixel = Color.black
        let (renderer, _) = try makeHarness { c in
            c.background(Color(r: 1, g: 1, b: 1))     // 全面白
            c.loadPixels()
            let red = Color(r: 1, g: 0, b: 0)
            c.set(-1, 1, red)                          // 行 1 の左外 → 行 0 の末尾を汚さない
            c.set(Self.size, 0, red)                   // 行 0 の右外 → 行 1 の先頭を汚さない
            c.set(0, -1, red)
            c.set(0, Self.size, red)
            firstOfRow1 = c.get(0, 1)
            lastOfRow0 = c.get(Self.size - 1, 0)
            firstPixel = c.get(0, 0)
        }
        renderer.renderFrame()

        let white = Color(r: 1, g: 1, b: 1)
        #expect(self.close(firstOfRow1, white), "行 1 の先頭が汚れた: \(firstOfRow1)")
        #expect(self.close(lastOfRow0, white), "行 0 の末尾が汚れた: \(lastOfRow0)")
        #expect(self.close(firstPixel, white), "先頭画素が汚れた: \(firstPixel)")
    }

    // MARK: - 往復（straight alpha・ADR-0012）

    /// `set` → `updatePixels` → `loadPixels` → `get` が一致すること。
    ///
    /// 半透明でも往復するのが要点（`pixels` は straight alpha なので、
    /// どちらかの側で premultiplied を混ぜると α < 1 の画素だけ沈む・#848）。
    @Test("set → updatePixels → loadPixels → get が半透明でも往復する")
    func setUpdateLoadGetRoundTrip() throws {
        let opaque = Color(r: 0.9, g: 0.3, b: 0.1)
        let translucent = Color(r: 0.2, g: 0.8, b: 0.4, alpha: 0.5)
        var gotOpaque = Color.black
        var gotTranslucent = Color.black
        let (renderer, _) = try makeHarness { c in
            c.blendMode(.opaque)                       // 置き換え（合成せずそのまま書く）
            c.noStroke()
            c.fill(Color(r: 1, g: 1, b: 1))
            c.rect(0, 0, Float(Self.size), Float(Self.size))
            c.loadPixels()
            c.set(10, 20, opaque)
            c.set(11, 21, translucent)
            c.updatePixels()
            c.loadPixels()                             // 書き戻した内容を読み直す
            gotOpaque = c.get(10, 20)
            gotTranslucent = c.get(11, 21)
        }
        renderer.renderFrame()

        #expect(self.close(gotOpaque, opaque), "不透明画素が往復しない: \(gotOpaque)")
        #expect(self.close(gotTranslucent, translucent),
                "半透明画素が往復しない（premultiplied が混ざっている）: \(gotTranslucent) — ADR-0012")
    }

    /// `set()` が実際にキャンバスへ出ること（`updatePixels()` を挟んで初めて絵が変わる）。
    @Test("set は updatePixels を挟んで初めてキャンバスへ出る")
    func setNeedsUpdatePixels() throws {
        func render(callingUpdatePixels: Bool) throws -> GoldenImage {
            let (renderer, _) = try makeHarness { c in
                c.background(Color(r: 0, g: 0, b: 0))
                c.loadPixels()
                for x in 0..<Self.size {
                    c.set(x, 32, Color(r: 1, g: 1, b: 0))   // 黄色の横線
                }
                if callingUpdatePixels { c.updatePixels() }
            }
            renderer.renderFrame()
            return try self.framebuffer(renderer)
        }

        let withoutUpdate = try render(callingUpdatePixels: false)
        let withUpdate = try render(callingUpdatePixels: true)
        func rgb(_ image: GoldenImage, _ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * image.width + x) * 4
            return (Int(image.rgba[i]), Int(image.rgba[i + 1]), Int(image.rgba[i + 2]))
        }
        let before = rgb(withoutUpdate, 32, 32)
        let after = rgb(withUpdate, 32, 32)
        #expect(before.0 < 20 && before.1 < 20,
                "updatePixels なしで絵が変わってはいけない: \(before)")
        #expect(after.0 > 200 && after.1 > 200 && after.2 < 50,
                "updatePixels 後は黄色の線が出るべき: \(after)")
    }

    // MARK: - 矩形版

    /// 矩形版は「要求したサイズ」の `MImage` を返し、左上が `get(x, y)` と一致する。
    ///
    /// 幅と高さを**別の値**にし、切り出し領域の中も左右で塗り分ける。正方形＋一様な色だと
    /// 行と列を取り違えていても通ってしまう。
    @Test("矩形 get は要求サイズの MImage を返し、画素が get(x, y) と一致する")
    func rectGetMatchesSinglePixelGet() throws {
        var rectImage: MImage?
        var topLeftFromCanvas = Color.black
        var bottomRightFromCanvas = Color.black
        let (renderer, _) = try makeHarness { c in
            c.background(Color(r: 0, g: 0, b: 1))
            c.noStroke()
            c.fill(Color(r: 1, g: 0.5, b: 0))
            c.rect(16, 24, 4, 4)                   // 切り出し領域の左半分だけオレンジ
            c.loadPixels()
            topLeftFromCanvas = c.get(16, 24)
            bottomRightFromCanvas = c.get(23, 27)
            rectImage = c.get(16, 24, 8, 4)        // 8 x 4（正方形にしない）
        }
        renderer.renderFrame()

        let img = try #require(rectImage)
        #expect(img.width == 8 && img.height == 4,
                "要求どおり 8x4 であるべき: \(img.width)x\(img.height)")
        img.loadPixels()
        #expect(self.close(img.get(0, 0), topLeftFromCanvas),
                "矩形の左上が get(16, 24) と一致しない: \(img.get(0, 0)) vs \(topLeftFromCanvas)")
        #expect(self.close(img.get(7, 3), bottomRightFromCanvas),
                "矩形の右下が get(23, 27) と一致しない: \(img.get(7, 3)) vs \(bottomRightFromCanvas)")
        // 左半分だけオレンジ。行と列を取り違えると塗り分けの向きが変わる。
        // 図形の縁は投影の半ピクセルオフセットで AA が乗るので、内側を見る。
        #expect(self.close(img.get(2, 1), Color(r: 1, g: 0.5, b: 0)),
                "切り出しの左半分はオレンジ: \(img.get(2, 1))")
        #expect(self.close(img.get(6, 1), Color(r: 0, g: 0, b: 1)),
                "切り出しの右半分は背景の青: \(img.get(6, 1))")
    }

    /// はみ出した矩形は**要求サイズのまま**返り、キャンバス外は透明（Processing 互換）。
    @Test("はみ出す矩形 get は要求サイズを保ち、キャンバス外は透明")
    func rectGetKeepsRequestedSizeAndFillsOutsideWithTransparent() throws {
        var rectImage: MImage?
        var negativeOrigin: MImage?
        let (renderer, _) = try makeHarness { c in
            c.background(Color(r: 1, g: 1, b: 1))
            c.loadPixels()
            rectImage = c.get(Self.size - 4, Self.size - 4, 8, 8)  // 右下が 4px はみ出す
            negativeOrigin = c.get(-4, -4, 8, 8)                   // 左上が 4px はみ出す
        }
        renderer.renderFrame()

        let img = try #require(rectImage)
        #expect(img.width == 8 && img.height == 8, "はみ出しても要求サイズを保つ")
        img.loadPixels()
        #expect(img.get(0, 0).a > 0.99, "キャンバス内の画素は不透明: \(img.get(0, 0))")
        #expect(img.get(7, 7).a == 0, "キャンバス外の画素は透明であるべき: \(img.get(7, 7))")
        #expect(img.get(4, 0).a == 0, "キャンバス外の画素は透明であるべき: \(img.get(4, 0))")

        let neg = try #require(negativeOrigin)
        #expect(neg.width == 8 && neg.height == 8)
        neg.loadPixels()
        #expect(neg.get(0, 0).a == 0, "負の原点側も透明: \(neg.get(0, 0))")
        #expect(neg.get(7, 7).a > 0.99, "キャンバスに掛かった側は不透明: \(neg.get(7, 7))")
    }

    /// 矩形版も straight alpha で返る（`MImage.get` と `SketchContext.get` が同じ世界）。
    @Test("矩形 get の半透明画素は straight alpha で返る")
    func rectGetReturnsStraightAlpha() throws {
        let translucent = Color(r: 0.2, g: 0.8, b: 0.4, alpha: 0.5)
        var rectImage: MImage?
        let (renderer, _) = try makeHarness { c in
            c.blendMode(.opaque)
            c.noStroke()
            c.fill(translucent)
            c.rect(0, 0, Float(Self.size), Float(Self.size))
            c.loadPixels()
            rectImage = c.get(8, 8, 4, 4)
        }
        renderer.renderFrame()

        let img = try #require(rectImage)
        img.loadPixels()
        let got = img.get(1, 1)
        #expect(self.close(got, translucent),
                "矩形 get が premultiplied のまま返している: \(got) — ADR-0012")
    }
}
