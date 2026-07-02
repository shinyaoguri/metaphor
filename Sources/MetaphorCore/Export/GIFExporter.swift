@preconcurrency import Metal
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// キャプチャしたフレームをアニメーションGIFファイルとしてエクスポートします。
///
/// Metal テクスチャのフレームをキャプチャし、アニメーションGIFとして書き出します。
/// ジェネラティブアート作品をSNSで共有するのに最適です。
///
/// ```swift
/// beginGIFRecord(fps: 15)
/// // ... draw frames ...
/// endGIFRecord("output.gif")
/// ```
///
/// 内部実装:
/// - フレームは ``beginRecord(fps:width:height:)`` で開いた一時ファイルに
///   `CGImageDestination` 経由で逐次書き込まれます（メモリ上に CGImage 配列を保持しません）。
/// - GPU 読み戻しは `addCompletedHandler` で非同期化され、メインスレッドの
///   `waitUntilCompleted` をなくしています。
/// - ステージングテクスチャはリングバッファ（既定 3 枚）で多重化、`DispatchSemaphore`
///   で in-flight 数を上限とし、上限到達時のみ `captureFrame` がブロックします（自然な backpressure）。
@MainActor
public final class GIFExporter {

    // MARK: - State

    /// 現在記録中かどうかを示すフラグ
    public private(set) var isRecording: Bool = false

    /// `captureFrame` の呼び出し回数（GIF への追加完了とは無関係）
    public private(set) var frameCount: Int = 0

    /// フレーム間の遅延時間（秒）
    private var frameDelay: Double = 1.0 / 15.0

    /// アクティブな逐次書き出し先（一時ファイル）
    private var destination: CGImageDestination?

    /// 一時ファイルの URL（`endRecord` で最終パスへ移動）
    private var temporaryURL: URL?

    // MARK: - Capture Pipeline

    /// in-flight フレームの上限。Metal の triple buffering と同じ N=3。
    private static let ringSize = 3

    /// ステージングテクスチャのリング（GPU→CPU 読み戻し用、shared storage）
    private var stagingRing: [MTLTexture] = []

    /// 次に使うステージングのインデックス
    private var ringIndex: Int = 0

    /// 現在のリングの寸法（変更時は再確保）
    private var ringWidth: Int = 0
    private var ringHeight: Int = 0

    /// in-flight フレーム数を ringSize に制限する semaphore
    private let inFlightSemaphore = DispatchSemaphore(value: ringSize)

    /// `CGImageDestinationAddImage` を直列化するキュー
    private let writerQueue = DispatchQueue(label: "metaphor.GIFExporter.writer")

    /// 未完了書き込みの追跡。`endRecord` で `wait()` してドレインしてからファイナライズする。
    ///
    /// セッションごとに `beginRecord` で新規作成します。共有のままだと、旧セッションの
    /// `notify` 待機中に次の録画の `enter()` が発火を先送りし、連続録画で旧ファイルの
    /// ファイナライズが実質保留になるためです。
    private var pendingWrites = DispatchGroup()

    /// キャプチャ幅（ピクセル、0 ならソーステクスチャ依存）
    private var captureWidth: Int = 0

    /// キャプチャ高さ（ピクセル、0 ならソーステクスチャ依存）
    private var captureHeight: Int = 0

    // MARK: - GIF Options

    /// GIFのループ回数（0は無限ループ）
    public var loopCount: Int = 0

    /// カラー量子化時のディザリング有効フラグ
    public var dithering: Bool = true

    public init() {}

    // MARK: - Public API

    /// GIF記録を開始します。
    ///
    /// 一時ファイルへの逐次書き出しが始まります。`endRecord(to:)` で最終的な
    /// 出力パスへリネームされます。
    /// - Parameters:
    ///   - fps: フレームレート（デフォルトは15）。
    ///   - width: キャプチャ幅（0の場合はソーステクスチャの幅を使用）。
    ///   - height: キャプチャ高さ（0の場合はソーステクスチャの高さを使用）。
    public func beginRecord(fps: Int = 15, width: Int = 0, height: Int = 0) {
        if isRecording { abortStreaming() }

        self.frameDelay = 1.0 / Double(max(1, fps))
        self.captureWidth = width
        self.captureHeight = height
        self.frameCount = 0
        self.ringIndex = 0
        self.ringWidth = 0
        self.ringHeight = 0
        self.stagingRing.removeAll()
        self.pendingWrites = DispatchGroup()

        let tempName = "metaphor_gif_\(UUID().uuidString).gif"
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(tempName)
        self.temporaryURL = tempURL

        guard let dest = CGImageDestinationCreateWithURL(
            tempURL as CFURL,
            UTType.gif.identifier as CFString,
            0,
            nil
        ) else {
            self.temporaryURL = nil
            return
        }

        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: loopCount
            ]
        ]
        CGImageDestinationSetProperties(dest, gifProperties as CFDictionary)

        self.destination = dest
        self.isRecording = true
    }

    /// Metal テクスチャから現在のフレームをキャプチャします。
    ///
    /// 内部で blit を発行して `addCompletedHandler` 経由で非同期に CPU へ
    /// 読み戻し、書き出しキューで CGImage 化と AddImage を行います。in-flight
    /// 数がリングサイズ (3) に達している場合のみ semaphore でブロックします。
    /// - Parameters:
    ///   - texture: キャプチャ対象の Metal テクスチャ。
    ///   - device: ステージングテクスチャ作成に使用する Metal デバイス。
    ///   - commandQueue: ブリットコマンドの発行に使用するコマンドキュー。
    public func captureFrame(texture: MTLTexture, device: MTLDevice, commandQueue: MTLCommandQueue) {
        guard isRecording else { return }
        guard let cmdBuf = commandQueue.makeCommandBuffer() else { return }
        captureFrame(texture: texture, device: device, commandBuffer: cmdBuf)
        cmdBuf.commit()
    }

    /// 既存のコマンドバッファに blit を同乗させて現在のフレームをキャプチャします。
    ///
    /// フレームのメインコマンドバッファ（コミット前）を渡すことで、
    /// 「今まさに描画されたフレーム」がキャプチャされます。自前のコマンドバッファを
    /// 即時コミットする ``captureFrame(texture:device:commandQueue:)`` は、同じ
    /// キュー上で先に実行されるため 1 フレーム前の内容を読みます。
    /// - Parameters:
    ///   - texture: キャプチャ対象の Metal テクスチャ。
    ///   - device: ステージングテクスチャ作成に使用する Metal デバイス。
    ///   - commandBuffer: blit を追加するコマンドバッファ（呼び出し側がコミットする）。
    public func captureFrame(texture: MTLTexture, device: MTLDevice, commandBuffer: MTLCommandBuffer) {
        guard isRecording, let dest = destination else { return }

        let w = captureWidth > 0 ? captureWidth : texture.width
        let h = captureHeight > 0 ? captureHeight : texture.height

        // 寸法変更時はリングを再構築（in-flight が完了するまで wait してから入れ替え）
        if stagingRing.isEmpty || ringWidth != w || ringHeight != h {
            // 既存リングのドレイン: 全 in-flight が signal するまで待つ
            for _ in 0..<Self.ringSize { inFlightSemaphore.wait() }
            let newRing = (0..<Self.ringSize).compactMap { _ in
                makeStaging(device: device, width: w, height: h)
            }
            // セマフォを ringSize 分だけ復帰
            for _ in 0..<Self.ringSize { inFlightSemaphore.signal() }

            guard newRing.count == Self.ringSize else {
                // 部分失敗: 寸法を確定させると次回の再構築がスキップされ、
                // stagingRing[ringIndex] が範囲外になる。状態を空へ戻して
                // 次フレームで全数を再試行する（このフレームはスキップ）。
                stagingRing.removeAll()
                ringWidth = 0
                ringHeight = 0
                metaphorWarning("GIFExporter: staging ring allocation failed (\(newRing.count)/\(Self.ringSize)); frame skipped")
                return
            }
            stagingRing = newRing
            ringWidth = w
            ringHeight = h
            ringIndex = 0
        }

        // Backpressure: in-flight が ringSize 未満になるまで待つ（通常は即時通過）
        inFlightSemaphore.wait()

        let staging = stagingRing[ringIndex]
        ringIndex = (ringIndex + 1) % Self.ringSize

        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            inFlightSemaphore.signal()
            return
        }
        if texture.width == staging.width && texture.height == staging.height {
            blit.copy(from: texture, to: staging)
        } else {
            // カスタムキャプチャサイズ: 全テクスチャ copy は寸法一致が必須なので、
            // 共通領域だけを領域指定でコピーする
            let copyW = min(texture.width, staging.width)
            let copyH = min(texture.height, staging.height)
            blit.copy(
                from: texture, sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: copyW, height: copyH, depth: 1),
                to: staging, destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
        }
        blit.endEncoding()

        // @Sendable クロージャ用のローカルコピー
        nonisolated(unsafe) let capturedDest = dest
        nonisolated(unsafe) let capturedStaging = staging
        let capturedDelay = frameDelay
        let queue = writerQueue
        let group = pendingWrites
        let semaphore = inFlightSemaphore

        group.enter()
        commandBuffer.addCompletedHandler { @Sendable _ in
            // すべての書き出し処理は writerQueue 上で直列化される
            queue.async {
                defer {
                    semaphore.signal()
                    group.leave()
                }
                guard let image = Self.makeCGImage(from: capturedStaging, width: w, height: h) else {
                    return
                }
                let frameProperties: [String: Any] = [
                    kCGImagePropertyGIFDictionary as String: [
                        kCGImagePropertyGIFDelayTime as String: capturedDelay,
                        // 多くのデコーダは DelayTime < 0.02s を 0.1s に丸めるため、
                        // 高 fps 用に Unclamped も併記する
                        kCGImagePropertyGIFUnclampedDelayTime as String: capturedDelay
                    ]
                ]
                CGImageDestinationAddImage(capturedDest, image, frameProperties as CFDictionary)
            }
        }

        frameCount += 1
    }

    /// 記録を停止し、キャプチャしたフレームをGIFファイルに書き出します。
    /// - Parameter path: 出力ファイルパス。
    /// - Throws: フレームがキャプチャされていない場合、またはファイル書き込みに失敗した場合に ``MetaphorError`` をスローします。
    public func endRecord(to path: String) throws {
        guard isRecording else { return }
        isRecording = false

        guard let dest = destination, let tempURL = temporaryURL else {
            throw MetaphorError.export(.destinationCreationFailed)
        }

        // すべての in-flight 書き込みが完了するまで待つ
        pendingWrites.wait()

        destination = nil
        temporaryURL = nil
        stagingRing.removeAll()
        ringWidth = 0
        ringHeight = 0

        guard frameCount > 0 else {
            try? FileManager.default.removeItem(at: tempURL)
            throw MetaphorError.export(.noFrames)
        }

        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: tempURL)
            throw MetaphorError.export(.finalizationFailed)
        }

        try Self.moveTemporaryFile(from: tempURL, to: path)
    }

    /// 記録を停止し、キャプチャしたフレームを非同期でGIFファイルに書き出します。
    ///
    /// メインスレッドをブロックしないよう、ドレイン・ファイナライズ・最終リネームを
    /// バックグラウンドスレッドで実行します。
    /// - Parameter path: 出力ファイルパス。
    /// - Throws: フレームがキャプチャされていない場合、またはファイル書き込みに失敗した場合に ``MetaphorError`` をスローします。
    public func endRecordAsync(to path: String) async throws {
        guard isRecording else { return }
        isRecording = false

        guard let dest = destination, let tempURL = temporaryURL else {
            throw MetaphorError.export(.destinationCreationFailed)
        }

        let capturedFrameCount = frameCount

        destination = nil
        temporaryURL = nil
        stagingRing.removeAll()
        ringWidth = 0
        ringHeight = 0

        nonisolated(unsafe) let capturedDest = dest
        let capturedTempURL = tempURL
        let group = pendingWrites
        let queue = writerQueue

        // バックグラウンドで in-flight をドレインしてからファイナライズ
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            group.notify(queue: queue) { cont.resume() }
        }

        try await Task.detached {
            guard capturedFrameCount > 0 else {
                try? FileManager.default.removeItem(at: capturedTempURL)
                throw MetaphorError.export(.noFrames)
            }
            guard CGImageDestinationFinalize(capturedDest) else {
                try? FileManager.default.removeItem(at: capturedTempURL)
                throw MetaphorError.export(.finalizationFailed)
            }
            try Self.moveTemporaryFile(from: capturedTempURL, to: path)
        }.value
    }

    // MARK: - Private

    private func makeStaging(device: MTLDevice, width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.storageMode = .shared
        desc.usage = [.shaderRead, .shaderWrite]
        return device.makeTexture(descriptor: desc)
    }

    /// shared storage のステージングから BGRA8 を読み出し、
    /// 1 パスで RGBA に並び替えつつ CGImage を構築する。
    nonisolated private static func makeCGImage(
        from staging: MTLTexture,
        width: Int,
        height: Int
    ) -> CGImage? {
        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 0, count: bytesPerRow * height)
        staging.getBytes(
            &pixelData,
            bytesPerRow: bytesPerRow,
            from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                           size: MTLSize(width: width, height: height, depth: 1)),
            mipmapLevel: 0
        )

        // BGRA → RGBA
        pixelData.withUnsafeMutableBufferPointer { buf in
            guard let p = buf.baseAddress else { return }
            for i in stride(from: 0, to: buf.count, by: 4) {
                let b = p[i]
                let r = p[i + 2]
                p[i] = r
                p[i + 2] = b
            }
        }

        // CGContext(data:) のポインタ規約（呼び出し中のみ有効）に従い、
        // makeImage() まで withUnsafeMutableBytes のスコープ内で完結させる
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return pixelData.withUnsafeMutableBytes { buf -> CGImage? in
            guard let context = CGContext(
                data: buf.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            return context.makeImage()
        }
    }

    nonisolated private static func moveTemporaryFile(from tempURL: URL, to path: String) throws {
        let destURL = URL(fileURLWithPath: path)
        let dir = destURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destURL)
    }

    private func abortStreaming() {
        // pending writes を待ち切る（再帰排除のため最低限）
        pendingWrites.wait()
        destination = nil
        if let tempURL = temporaryURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        temporaryURL = nil
        stagingRing.removeAll()
        ringWidth = 0
        ringHeight = 0
        isRecording = false
        frameCount = 0
    }
}
