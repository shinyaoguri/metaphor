import CoreGraphics
import Metal
import os
import QuartzCore

/// Pulls the currently drawn frame of a headless run to the CPU, but only while the menu is open.
///
/// With no window, the numbers in the status item (measured fps, frame count)
/// do not tell you **what is being drawn**. Reading the frame back from GPU to
/// CPU every frame to answer that would break the Probe performance contract
/// (Issue #118: do not intrude on the runtime).
///
/// So the work is confined to the time the menu is open:
///
/// - While ``isCapturing`` is `false`, ``post(texture:commandBuffer:)`` returns
///   after **a single Bool check** — the cost while closed is effectively zero.
///   The one exception is the **very first frame**, which is taken either way: a
///   piece using `noLoop()` draws no further frames, so skipping it would leave
///   the menu without a picture forever.
/// - While open, ``minimumInterval`` thins the rate out and only one read-back is
///   in flight at a time (the previous one has to finish first).
/// - Downscaling happens on the GPU (the built-in blit shader draws into a small
///   texture), so what comes back is always one thumbnail — the full frame never
///   reaches the CPU.
@MainActor
final class HeadlessPreviewTap: MetaphorPlugin {
    /// The stable plugin identifier.
    static let id = "org.metaphor.headless-preview"

    let pluginID: String = HeadlessPreviewTap.id

    /// Whether to capture. Set to `true` only while the menu is open.
    var isCapturing = false {
        didSet {
            guard isCapturing != oldValue else { return }
            // 次に開いたときは待たずに撮り直す（開いた直後に古い絵のままにしない）。
            if isCapturing { lastCaptureTime = 0 }
        }
    }

    /// The most recently captured picture, or `nil` if none has been taken yet.
    ///
    /// The GPU completion handler (on another thread) drops read-back pixels into
    /// ``pending``, and they are turned into an image when this property is read
    /// — that is, when the menu is drawn. The handler deliberately **does not
    /// hand them to the main actor asynchronously**: when the main actor is busy,
    /// that hand-off can be delayed indefinitely (frames were actually lost this
    /// way under CI's parallel execution).
    var latestFrame: CGImage? {
        if let readback = pending.withLock({ $0 }), readback.generation != cachedGeneration {
            cachedImage = Self.makeImage(
                bgra: readback.bytes, width: readback.width, height: readback.height
            )
            cachedGeneration = readback.generation
        }
        return cachedImage
    }

    /// One frame of read-back pixels, handed from the completion handler to the main actor.
    private struct Readback: Sendable {
        let bytes: [UInt8]
        let width: Int
        let height: Int
        /// Which frame this is — the marker that limits image conversion to newly arrived pixels.
        let generation: UInt64
    }

    /// The pixels the completion handler left behind most recently.
    private let pending = OSAllocatedUnfairLock<Readback?>(initialState: nil)

    /// Whether a read-back is in flight (held behind a lock, since the completion handler clears it).
    private let inFlight = OSAllocatedUnfairLock<Bool>(initialState: false)

    private var cachedImage: CGImage?
    private var cachedGeneration: UInt64 = 0
    private var generation: UInt64 = 0

    /// How many times downscale + read-back actually ran (so tests can pin "does nothing while closed").
    private(set) var captureCount = 0

    /// The box the thumbnail fits into, in pixels — twice the logical size, to allow for Retina.
    private let box: (width: Int, height: Int)

    /// The minimum interval between captures, in seconds.
    private let minimumInterval: Double

    private weak var renderer: MetaphorRenderer?
    private var pipeline: MTLRenderPipelineState?
    private var staging: MTLTexture?
    private var lastCaptureTime: Double = 0
    private var capturedInitialFrame = false
    private var warnedUnsupportedFormat = false

    /// - Parameters:
    ///   - box: The box the thumbnail fits into, in pixels.
    ///   - fps: The refresh rate while the menu is open.
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
            let pipeline = ensurePipeline()
        else { return }

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
                guard let base = buffer.baseAddress else {
                    count = 0
                    return
                }
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

    /// Builds a `CGImage` from BGRA8 pixels.
    ///
    /// The read-back content is premultiplied (ADR-0012), so the declaration
    /// matches that — the same reason ProbeWriter's PNG export does.
    static func makeImage(bgra: [UInt8], width: Int, height: Int) -> CGImage? {
        var pixels = bgra
        let bitmapInfo =
            CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        guard
            let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo
            )
        else { return nil }
        return context.makeImage()
    }

    /// The thumbnail size that fits the box (a pure function, covered by tests).
    ///
    /// Fits inside the box while preserving the aspect ratio, and never scales up
    /// beyond the original. Rounds so the result never falls below 1 px.
    static func thumbnailSize(
        width: Int, height: Int, box: (width: Int, height: Int)
    ) -> (width: Int, height: Int) {
        guard width > 0, height > 0, box.width > 0, box.height > 0 else { return (1, 1) }
        let scale = min(
            Double(box.width) / Double(width),
            Double(box.height) / Double(height),
            1.0
        )
        return (
            max(Int((Double(width) * scale).rounded()), 1),
            max(Int((Double(height) * scale).rounded()), 1)
        )
    }

    /// Prepares the destination texture for the downscale, rebuilding it when the size changes.
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
            metaphorDiagnostic(
                "headless preview: could not create a \(width)×\(height) thumbnail texture")
            return nil
        }
        texture.label = "metaphor.headless-preview"
        staging = texture
        return texture
    }

    /// Prepares the pipeline used for the downscale (the built-in blit shader).
    private func ensurePipeline() -> MTLRenderPipelineState? {
        if let pipeline { return pipeline }
        guard let renderer else { return nil }
        guard
            let vertexFn = renderer.shaderLibrary.function(
                named: BuiltinShaders.FunctionName.blitVertex, from: ShaderLibrary.BuiltinKey.blit
            ),
            let fragmentFn = renderer.shaderLibrary.function(
                named: BuiltinShaders.FunctionName.blitFragment, from: ShaderLibrary.BuiltinKey.blit
            )
        else {
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
