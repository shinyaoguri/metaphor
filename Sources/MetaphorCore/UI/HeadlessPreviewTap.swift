import CoreGraphics
import Metal
import os
import QuartzCore

/// ヘッドレス実行の「いま描かれている絵」を、メニューを開いている間だけ CPU 側へ取り出すプラグイン。
///
/// ウィンドウが無い実行では、状態項目の数値（実測 fps・frame 数）だけでは
/// **何が描かれているか**まで分かりません。とはいえ、そのために毎フレーム GPU→CPU の
/// 読み戻しを走らせると Probe の性能契約（Issue #118: ランタイムを侵さない）を破ります。
///
/// そこで「メニューが開いている間だけ」に絞ります:
///
/// - ``isCapturing`` が `false` の間、``post(texture:commandBuffer:)`` は **Bool 1 回**で戻る
///   （＝閉じているときのコストは実質ゼロ）。例外は**最初の 1 枚**だけで、これは開閉に
///   関わらず取る（`noLoop()` の作品は以降フレームを描かないので、ここで取らないと
///   メニューに永久に絵が出ない）
/// - 開いている間も ``minimumInterval`` で間引き、読み戻しは 1 枚ずつ（前の完了を待つ）
/// - 縮小は GPU 側（組み込みの blit シェーダで小さなテクスチャへ描く）で済ませるので、
///   読み戻すのは常にサムネイル 1 枚ぶん（フルフレームは CPU へ渡らない）
@MainActor
final class HeadlessPreviewTap: MetaphorPlugin {
    /// 安定したプラグイン識別子。
    static let id = "org.metaphor.headless-preview"

    let pluginID: String = HeadlessPreviewTap.id

    /// 取り出しを行うか。メニューが開いている間だけ `true` にします。
    var isCapturing = false {
        didSet {
            guard isCapturing != oldValue else { return }
            // 次に開いたときは待たずに撮り直す（開いた直後に古い絵のままにしない）。
            if isCapturing { lastCaptureTime = 0 }
        }
    }

    /// 直近に取り出せた絵。まだ 1 枚も撮れていなければ `nil`。
    ///
    /// 読み戻したピクセルは GPU の完了ハンドラ（別スレッド）から ``pending`` へ置かれ、
    /// 絵にするのはここを読んだとき（＝メニューを描くとき）です。**完了ハンドラから
    /// メインアクターへ非同期に渡さない**のは、メインアクターが混んでいると受け渡しが
    /// いつまでも走らないため（CI の並列実行で実際に取りこぼした）。
    var latestFrame: CGImage? {
        if let readback = pending.withLock({ $0 }), readback.generation != cachedGeneration {
            cachedImage = Self.makeImage(
                bgra: readback.bytes, width: readback.width, height: readback.height
            )
            cachedGeneration = readback.generation
        }
        return cachedImage
    }

    /// 読み戻したピクセル 1 枚ぶん（完了ハンドラ ⇄ メインアクターの受け渡し用）。
    private struct Readback: Sendable {
        let bytes: [UInt8]
        let width: Int
        let height: Int
        /// 何枚目か。絵への変換を「新しいものが来たときだけ」に絞るための印。
        let generation: UInt64
    }

    /// 完了ハンドラが最後に置いていったピクセル。
    private let pending = OSAllocatedUnfairLock<Readback?>(initialState: nil)

    /// 読み戻しが進行中か（完了ハンドラから下ろすのでロック越しに持つ）。
    private let inFlight = OSAllocatedUnfairLock<Bool>(initialState: false)

    private var cachedImage: CGImage?
    private var cachedGeneration: UInt64 = 0
    private var generation: UInt64 = 0

    /// 縮小と読み戻しを実際に走らせた回数（「閉じている間は何もしない」をテストで押さえるため）。
    private(set) var captureCount = 0

    /// サムネイルを収める箱（ピクセル）。Retina を見込んで論理サイズの 2 倍で持ちます。
    private let box: (width: Int, height: Int)

    /// 取り出しの最小間隔（秒）。
    private let minimumInterval: Double

    private weak var renderer: MetaphorRenderer?
    private var pipeline: MTLRenderPipelineState?
    private var staging: MTLTexture?
    private var lastCaptureTime: Double = 0
    private var capturedInitialFrame = false
    private var warnedUnsupportedFormat = false

    /// - Parameters:
    ///   - box: サムネイルを収める箱（ピクセル）。
    ///   - fps: 開いている間の更新レート。
    init(box: (width: Int, height: Int) = (480, 360), fps: Double = 8) {
        self.box = box
        self.minimumInterval = 1.0 / max(fps, 1)
    }

    // MARK: - MetaphorPlugin

    func onAttach(renderer: MetaphorRenderer) {
        self.renderer = renderer
    }

    func onDetach() {
        staging = nil
        pipeline = nil
        pending.withLock { $0 = nil }
        cachedImage = nil
    }

    func post(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        // 閉じている間のコストはこの 1 行だけ（最初の 1 枚を除く）。
        guard isCapturing || !capturedInitialFrame, !inFlight.withLock({ $0 }) else { return }

        let now = CACurrentMediaTime()
        guard now - lastCaptureTime >= minimumInterval else { return }

        guard texture.pixelFormat == .bgra8Unorm else {
            if !warnedUnsupportedFormat {
                warnedUnsupportedFormat = true
                metaphorDiagnostic(
                    "headless preview: output texture format \(texture.pixelFormat) is not "
                    + "supported (bgra8Unorm only); the menu will show no thumbnail"
                )
            }
            return
        }

        let size = Self.thumbnailSize(
            width: texture.width, height: texture.height, box: box
        )
        guard let staging = ensureStaging(width: size.width, height: size.height),
              let pipeline = ensurePipeline() else { return }

        // 縮小は GPU で行う（組み込み blit シェーダ = リニア補間つきのフルスクリーン矩形）。
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = staging
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "metaphor.headless-preview.downscale"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        lastCaptureTime = now
        capturedInitialFrame = true
        captureCount += 1
        generation += 1
        inFlight.withLock { $0 = true }

        // `staging` を完了ハンドラへ持ち込むための箱（Issue #328 の使い方に従う）。
        // 安全の根拠: この 1 枚は `readbackInFlight` が下りるまで作り直さず、書くのは
        // GPU、読むのは完了後のハンドラだけで、同時に触る経路が無い。
        let handoff = UncheckedSendableBox(staging)
        let width = size.width
        let height = size.height
        let generation = self.generation
        let pending = self.pending
        let inFlight = self.inFlight
        commandBuffer.addCompletedHandler { _ in
            // 読み戻すのはサムネイル 1 枚ぶん（480×360 で 675KB 以下）。
            let pixels = [UInt8](unsafeUninitializedCapacity: width * height * 4) { buffer, count in
                guard let base = buffer.baseAddress else { count = 0; return }
                handoff.value.getBytes(
                    base,
                    bytesPerRow: width * 4,
                    from: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0
                )
                count = width * height * 4
            }
            // 撮り終える前にメニューが閉じても捨てない（読み戻しは済んでいるうえ、
            // 次に開いたときの「1 枚目が来るまでの空白」を埋められる）。
            pending.withLock {
                $0 = Readback(bytes: pixels, width: width, height: height, generation: generation)
            }
            inFlight.withLock { $0 = false }
        }
    }

    // MARK: - Helpers

    /// BGRA8 ピクセルから `CGImage` を作ります。
    ///
    /// 読み戻した中身は premultiplied（ADR-0012）なので、宣言もそれに合わせます
    /// （ProbeWriter の PNG 書き出しと同じ理由）。
    static func makeImage(bgra: [UInt8], width: Int, height: Int) -> CGImage? {
        var pixels = bgra
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else { return nil }
        return context.makeImage()
    }

    /// 箱に収まるサムネイルの大きさ（純関数・テスト対象）。
    ///
    /// アスペクト比を保ったまま箱に内接させ、拡大はしません（元より大きくならない）。
    /// 1px を下回らないよう丸めます。
    static func thumbnailSize(
        width: Int, height: Int, box: (width: Int, height: Int)
    ) -> (width: Int, height: Int) {
        guard width > 0, height > 0, box.width > 0, box.height > 0 else { return (1, 1) }
        let scale = min(
            Double(box.width) / Double(width),
            Double(box.height) / Double(height),
            1.0
        )
        return (max(Int((Double(width) * scale).rounded()), 1),
                max(Int((Double(height) * scale).rounded()), 1))
    }

    /// 縮小先のテクスチャを用意します（大きさが変わったら作り直す）。
    private func ensureStaging(width: Int, height: Int) -> MTLTexture? {
        if let staging, staging.width == width, staging.height == height { return staging }
        guard let device = renderer?.device else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        // Apple Silicon 専用（ユニファイドメモリ）なので、GPU が書いた中身を
        // synchronize 無しでそのまま読める。
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            metaphorDiagnostic("headless preview: could not create a \(width)×\(height) thumbnail texture")
            return nil
        }
        texture.label = "metaphor.headless-preview"
        staging = texture
        return texture
    }

    /// 縮小に使うパイプライン（組み込みの blit シェーダ）を用意します。
    private func ensurePipeline() -> MTLRenderPipelineState? {
        if let pipeline { return pipeline }
        guard let renderer else { return nil }
        guard let vertexFn = renderer.shaderLibrary.function(
            named: BuiltinShaders.FunctionName.blitVertex, from: ShaderLibrary.BuiltinKey.blit
        ), let fragmentFn = renderer.shaderLibrary.function(
            named: BuiltinShaders.FunctionName.blitFragment, from: ShaderLibrary.BuiltinKey.blit
        ) else {
            metaphorDiagnostic("headless preview: built-in blit shader is unavailable")
            return nil
        }
        do {
            // 描き先はサムネイル 1 枚だけなので深度もマルチサンプルも要らない。
            let state = try PipelineFactory(device: renderer.device)
                .vertex(vertexFn)
                .fragment(fragmentFn)
                .colorFormat(.bgra8Unorm)
                .noDepth()
                .sampleCount(1)
                .build()
            pipeline = state
            return state
        } catch {
            metaphorDiagnostic("headless preview: could not build the downscale pipeline: \(error)")
            return nil
        }
    }
}
