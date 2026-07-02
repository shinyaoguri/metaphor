@preconcurrency import Metal
import Foundation

/// 各フレームを連番PNGファイルとしてエクスポートします。
///
/// `beginSequence()` で記録を開始し、`endSequence()` で停止します。
/// 記録中は各フレームが自動的にPNGファイルとして書き出されます。
///
/// ```swift
/// // In setup()
/// beginRecord()
///
/// // After 100 frames
/// endRecord()
/// ```
@MainActor
public final class FrameExporter {
    /// 現在記録中かどうかを示すフラグ
    public private(set) var isRecording: Bool = false

    /// 現在のフレームインデックス
    private var frameIndex: Int = 0

    /// 出力ディレクトリパス
    private var outputDirectory: String = ""

    /// printf形式のファイル名パターン
    private var filenamePattern: String = "frame_%05d.png"

    /// デフォルトのファイル名パターン
    private static let defaultPattern = "frame_%05d.png"

    /// PNG エンコード + ディスク書き込みを直列化するキュー
    private let writerQueue = DispatchQueue(label: "metaphor.FrameExporter.writer")

    /// 非同期 PNG 書き込みの同時保留数上限（超過時は完了ハンドラ内で同期書き込みに
    /// フォールバックして自然な backpressure をかけ、メモリの無制限成長を防ぐ）
    private let pendingWriteSemaphore = DispatchSemaphore(value: 4)

    public init() {}

    /// フレームの連番PNGシーケンスのエクスポートを開始します。
    /// - Parameters:
    ///   - directory: 出力ディレクトリ（存在しない場合は自動作成されます）。
    ///   - pattern: ファイル名パターン。整数フォーマット指定子（`%d` / `%05d` 等）を
    ///     ちょうど 1 個含む必要があります。不正なパターンは warning を出して
    ///     デフォルト（`frame_%05d.png`）にフォールバックします。
    public func beginSequence(directory: String, pattern: String = "frame_%05d.png") {
        self.outputDirectory = directory
        if Self.isValidPattern(pattern) {
            self.filenamePattern = pattern
        } else {
            metaphorWarning(
                "FrameExporter: invalid filename pattern '\(pattern)' " +
                "(must contain exactly one integer format specifier like %05d); " +
                "using '\(Self.defaultPattern)'"
            )
            self.filenamePattern = Self.defaultPattern
        }
        self.frameIndex = 0
        self.isRecording = true

        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: directory),
            withIntermediateDirectories: true
        )
    }

    /// ファイル名パターンを検証します。
    ///
    /// `String(format:)` にユーザー入力をそのまま渡すため、`%@`（クラッシュ）や
    /// `%d` の欠落（全フレーム同名で上書き）を防ぐ必要があります。
    /// 整数変換（d/u/x/X/o、フラグ・幅指定つき可）ちょうど 1 個のみを許可します。
    static func isValidPattern(_ pattern: String) -> Bool {
        var conversions = 0
        var i = pattern.startIndex
        while i < pattern.endIndex {
            guard pattern[i] == "%" else {
                i = pattern.index(after: i)
                continue
            }
            let next = pattern.index(after: i)
            guard next < pattern.endIndex else { return false }
            if pattern[next] == "%" {
                // リテラルの %% はスキップ
                i = pattern.index(after: next)
                continue
            }
            // フラグ・幅（0-9 + - # 空白）を読み飛ばし、整数変換指定子で終わること
            var j = next
            while j < pattern.endIndex, "0123456789+- #".contains(pattern[j]) {
                j = pattern.index(after: j)
            }
            guard j < pattern.endIndex, "duxXo".contains(pattern[j]) else { return false }
            conversions += 1
            i = pattern.index(after: j)
        }
        return conversions == 1
    }

    /// フレームのエクスポートを停止します。
    public func endSequence() {
        isRecording = false
    }

    /// 現在のフレームをキャプチャします（MetaphorRenderer.renderFrame() から呼ばれます）。
    func captureFrame(
        sourceTexture: MTLTexture,
        stagingTexture: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        width: Int,
        height: Int,
        completionGroup: DispatchGroup? = nil
    ) {
        guard isRecording else { return }

        let currentFrame = frameIndex
        frameIndex += 1

        let filename = String(format: filenamePattern, currentFrame)
        let path = URL(fileURLWithPath: outputDirectory).appendingPathComponent(filename).path

        if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            blitEncoder.copy(
                from: sourceTexture,
                sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: width, height: height, depth: 1),
                to: stagingTexture,
                destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blitEncoder.endEncoding()
        }

        let queue = writerQueue
        let semaphore = pendingWriteSemaphore

        completionGroup?.enter()
        commandBuffer.addCompletedHandler { _ in
            // ステージングからの読み出し（軽い memcpy）だけを完了ハンドラ内で行い、
            // PNG エンコード + ディスク I/O は writerQueue へ逃がす。これにより
            // completionGroup（= インフライトスロットの返却）がディスク I/O に
            // 律速されない。保留数が上限を超えた場合のみ同期書き込みへフォールバック
            // して backpressure をかける（メモリの無制限成長を防止）。
            let bytesPerRow = width * 4
            var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
            stagingTexture.getBytes(
                &pixels,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
            completionGroup?.leave()

            if semaphore.wait(timeout: .now()) == .success {
                let captured = pixels
                queue.async {
                    defer { semaphore.signal() }
                    MetaphorRenderer.writePNG(
                        bgraPixels: captured, width: width, height: height, path: path
                    )
                }
            } else {
                // 書き込みが追いついていない: このフレームは同期書き込み
                MetaphorRenderer.writePNG(
                    bgraPixels: pixels, width: width, height: height, path: path
                )
            }
        }
    }
}
