import AVFoundation
import CoreVideo
import Foundation
import Metal

// MARK: - PlaybackHolder

/// アクター境界を越えて安全にクリーンアップするために AVPlayer のライフサイクルを管理します。
///
/// AVPlayer の pause 操作はスレッドセーフです。
private final class PlaybackHolder: @unchecked Sendable {
    let player: AVPlayer
    let playerItem: AVPlayerItem
    let videoOutput: AVPlayerItemVideoOutput

    init(player: AVPlayer, playerItem: AVPlayerItem, videoOutput: AVPlayerItemVideoOutput) {
        self.player = player
        self.playerItem = playerItem
        self.videoOutput = videoOutput
    }

    deinit {
        player.pause()
    }
}

// MARK: - VideoPlayerError

/// ビデオプレーヤーの操作中に発生するエラー。
public enum VideoPlayerError: Error, LocalizedError, Sendable {
    /// 指定されたパスにビデオファイルが見つからなかった。
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            "Video file not found: \(path)"
        }
    }
}

// MARK: - VideoPlayer

/// ビデオファイルの再生とフレーム取得を管理します。
///
/// AVPlayer を使用してビデオを再生し、CVMetalTextureCache 経由で
/// ゼロコピーの Metal テクスチャとしてフレームを提供します。
///
/// ```swift
/// let video = try loadVideo("/path/to/video.mp4")
/// video.loop()
///
/// // draw() 内:
/// video.update()
/// image(video, 0, 0, width, height)
/// ```
@MainActor
public final class VideoPlayer {

    // MARK: - Public Properties

    /// 現在のビデオフレームの Metal テクスチャ。
    /// `update()` 呼び出し後に利用可能になります。
    public private(set) var texture: MTLTexture?

    /// ビデオが現在再生中かどうか。
    public private(set) var isPlaying: Bool = false

    /// ループ再生の有効・無効を制御します。
    public var isLooping: Bool = false

    /// 少なくとも1フレームがデコードされたかどうか。
    public private(set) var isAvailable: Bool = false

    /// ビデオの総再生時間（秒）。
    public let duration: Double

    /// 現在の再生位置（秒）。setter でフレーム精度のシークを行います。
    public var position: Double {
        get {
            CMTimeGetSeconds(playback.player.currentTime())
        }
        set {
            let time = CMTime(seconds: max(0, min(newValue, duration)), preferredTimescale: 600)
            playback.player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    /// 再生速度を制御します（0.25〜4.0）。
    public var rate: Float {
        get { _rate }
        set {
            _rate = max(0.25, min(4.0, newValue))
            if isPlaying {
                playback.player.rate = _rate
            }
        }
    }

    /// オーディオのゲインを制御します（0.0〜1.0）。
    public var gain: Float {
        get { playback.player.volume }
        set { playback.player.volume = max(0, min(1, newValue)) }
    }

    /// ビデオフレームの幅（ポイント単位）。
    public private(set) var width: Float = 0

    /// ビデオフレームの高さ（ポイント単位）。
    public private(set) var height: Float = 0

    // MARK: - Private State

    private let playback: PlaybackHolder
    private var textureCache: CVMetalTextureCache?
    private var _rate: Float = 1.0
    private var notificationObserver: NSObjectProtocol?

    // CVMetalTexture の参照を保持（MTLTexture のバッキングストアとして必要）
    private var currentCVTexture: CVMetalTexture?

    // MARK: - Initialization

    /// 指定パスからビデオファイルを読み込みます。
    ///
    /// - Parameters:
    ///   - path: ビデオファイルのファイルシステムパス。
    ///   - device: テクスチャキャッシュ作成に使用する Metal デバイス。
    /// - Throws: ファイルが存在しない場合に ``VideoPlayerError/fileNotFound(_:)`` をスローします。
    public init(path: String, device: MTLDevice) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw VideoPlayerError.fileNotFound(path)
        }

        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)

        // ビデオ出力を BGRA フォーマットで構成
        let outputSettings: [String: Any] = [
            String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA,
            String(kCVPixelBufferMetalCompatibilityKey): true,
        ]
        let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: outputSettings)
        playerItem.add(videoOutput)

        let player = AVPlayer(playerItem: playerItem)
        player.actionAtItemEnd = .pause

        self.playback = PlaybackHolder(
            player: player,
            playerItem: playerItem,
            videoOutput: videoOutput
        )

        // ビデオトラックの寸法と再生時間を取得。
        // `Sketch.setup()` を async 化しない方針のため init は同期のまま、
        // macOS 13+ の async ローダーを semaphore で同期待ちする。
        // ローカルファイル専用なのでブロッキング時間は実質ゼロ。
        let metadata = Self.loadAssetMetadataSync(asset)
        let assetDuration = metadata.duration
        if let naturalSize = metadata.naturalSize {
            self.width = Float(naturalSize.width)
            self.height = Float(naturalSize.height)
        }

        let durationSeconds = CMTimeGetSeconds(assetDuration)
        self.duration = durationSeconds.isNaN ? 0 : durationSeconds

        // CVMetalTextureCache を作成
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.textureCache = cache

        // ループ用の再生終了通知を登録
        self.notificationObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handlePlaybackEnd()
            }
        }
    }

    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// `AVURLAsset` のトラック・再生時間・サイズを同期的に取り出すヘルパー。
    /// macOS 13+ の async API を `DispatchSemaphore` で待つことで、
    /// 同期 init の互換性を保ちつつ非推奨 API の警告を回避する。
    nonisolated private static func loadAssetMetadataSync(
        _ asset: AVURLAsset
    ) -> (track: AVAssetTrack?, duration: CMTime, naturalSize: CGSize?) {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var loadedTrack: AVAssetTrack?
        nonisolated(unsafe) var loadedDuration: CMTime = .zero
        nonisolated(unsafe) var loadedSize: CGSize?

        Task.detached {
            let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
            loadedTrack = tracks.first
            if let track = tracks.first {
                loadedSize = try? await track.load(.naturalSize)
            }
            loadedDuration = (try? await asset.load(.duration)) ?? .zero
            semaphore.signal()
        }
        semaphore.wait()
        return (loadedTrack, loadedDuration, loadedSize)
    }

    // MARK: - Playback Control

    /// ビデオ再生を開始します。
    public func play() {
        playback.player.rate = _rate
        isPlaying = true
    }

    /// ビデオ再生を一時停止します。現在の位置は維持されます。
    public func pause() {
        playback.player.pause()
        isPlaying = false
    }

    /// ビデオ再生を停止し、先頭に巻き戻します。
    public func stop() {
        playback.player.pause()
        isPlaying = false
        position = 0
    }

    /// ループ再生を有効にして再生を開始します。
    public func loop() {
        isLooping = true
        play()
    }

    // MARK: - Frame Update

    /// 現在の再生位置に基づいてビデオフレームを更新します。
    ///
    /// `draw()` メソッドの先頭で毎フレーム呼び出してください。
    /// 新しいフレームが利用可能な場合、`texture` プロパティが更新されます。
    public func update() {
        guard isPlaying else { return }

        let currentTime = playback.player.currentTime()
        guard playback.videoOutput.hasNewPixelBuffer(forItemTime: currentTime) else { return }

        guard let pixelBuffer = playback.videoOutput.copyPixelBuffer(
            forItemTime: currentTime, itemTimeForDisplay: nil
        ) else { return }

        guard let cache = textureCache else { return }

        let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
        let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pixelBuffer, nil,
            .bgra8Unorm, bufferWidth, bufferHeight, 0, &cvTexture
        )

        guard status == kCVReturnSuccess, let cvTex = cvTexture else { return }

        self.currentCVTexture = cvTex
        self.texture = CVMetalTextureGetTexture(cvTex)
        self.width = Float(bufferWidth)
        self.height = Float(bufferHeight)
        self.isAvailable = true
    }

    // MARK: - Private

    private func handlePlaybackEnd() {
        if isLooping {
            playback.player.seek(to: .zero)
            playback.player.play()
            playback.player.rate = _rate
        } else {
            isPlaying = false
        }
    }
}
