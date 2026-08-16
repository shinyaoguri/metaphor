import AVFoundation
import CoreVideo
import Foundation
import MetaphorLog
import Metal
import ObjectiveC.runtime

// MARK: - NotificationObserverToken

/// Owns a block-based `NotificationCenter` observer token and unregisters it on
/// deallocation.
///
/// Block-based observers are not auto-removed, so the token has to outlive the
/// registration and be handed back to `NotificationCenter`. Holding it here (rather
/// than in a `@MainActor` property that `deinit` reads) keeps teardown correct under
/// strict concurrency: `deinit` is `nonisolated`, so it cannot touch actor-isolated
/// storage of a non-`Sendable` type.
///
/// `@unchecked Sendable` rationale: the token is stored once, never handed out, and
/// its only use is `NotificationCenter.removeObserver(_:)` — and `NotificationCenter`
/// is documented as thread-safe. There is no mutable state to race on.
/// (Internal rather than private so the teardown contract can be unit-tested.)
final class NotificationObserverToken: @unchecked Sendable {
    private let token: any NSObjectProtocol
    private let center: NotificationCenter

    init(_ token: any NSObjectProtocol, center: NotificationCenter = .default) {
        self.token = token
        self.center = center
    }

    deinit {
        center.removeObserver(token)
    }
}

// MARK: - PlaybackHolder

/// Manages the lifecycle of `AVPlayer` for safe cleanup across actor boundaries.
///
/// The pause operation on `AVPlayer` is thread-safe.
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

/// Errors that can occur during video player operations.
public enum VideoPlayerError: Error, LocalizedError, Sendable {
    /// No video file was found at the specified path.
    case fileNotFound(String)
    /// Loading or playing the item failed (e.g. a corrupt file or unsupported codec).
    case playbackFailed(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            "Video file not found: \(path)"
        case .playbackFailed(let reason):
            "Video playback failed: \(reason)"
        }
    }
}

// MARK: - スレッドセーフなエラーボックス

/// Carries errors observed via KVO (on any thread) to the main thread's poll-style API.
private final class VideoErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var error: (any Error)?

    func store(_ error: any Error) {
        lock.lock()
        self.error = error
        lock.unlock()
    }

    var value: (any Error)? {
        lock.lock()
        defer { lock.unlock() }
        return error
    }
}

// MARK: - VideoPlayer

/// Manages playback and frame retrieval for a video file.
///
/// Plays a video using `AVPlayer` and provides frames as zero-copy Metal
/// textures via `CVMetalTextureCache`.
///
/// ```swift
/// let video = try loadVideo("/path/to/video.mp4")
/// video.loop()
///
/// // inside draw():
/// video.update()
/// image(video, 0, 0, width, height)
/// ```
@MainActor
public final class VideoPlayer {

    // MARK: - Public Properties

    /// The Metal texture for the current video frame.
    /// Available after calling `update()`.
    public private(set) var texture: MTLTexture?

    /// Whether the video is currently playing.
    public private(set) var isPlaying: Bool = false

    /// Controls whether looping playback is enabled.
    public var isLooping: Bool = false

    /// Whether at least one frame has been decoded.
    public private(set) var isAvailable: Bool = false

    /// The item's loading/playback error (e.g. a corrupt file or unsupported codec).
    ///
    /// `AVPlayerItem` failures resolve asynchronously, so check this
    /// property the same way you check ``update()`` inside `draw()`
    /// (previously, a failure was a silent failure — ``isAvailable``
    /// stayed false and no frames ever arrived).
    public var lastError: (any Error)? { errorBox.value }

    /// The video's total duration (seconds).
    public let duration: Double

    /// The current playback position (seconds). The setter performs a frame-accurate seek.
    public var position: Double {
        get {
            CMTimeGetSeconds(playback.player.currentTime())
        }
        set {
            let time = CMTime(seconds: max(0, min(newValue, duration)), preferredTimescale: 600)
            playback.player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    /// Controls the playback rate (0.25-4.0).
    public var rate: Float {
        get { _rate }
        set {
            _rate = max(0.25, min(4.0, newValue))
            if isPlaying {
                playback.player.rate = _rate
            }
        }
    }

    /// Controls the audio gain (0.0-1.0).
    public var gain: Float {
        get { playback.player.volume }
        set { playback.player.volume = max(0, min(1, newValue)) }
    }

    /// The video frame width (in points).
    public private(set) var width: Float = 0

    /// The video frame height (in points).
    public private(set) var height: Float = 0

    // MARK: - Private State

    private let playback: PlaybackHolder
    private var textureCache: CVMetalTextureCache?
    private var _rate: Float = 1.0
    /// Released together with the player; the holder's `deinit` unregisters the observer.
    private var notificationObserver: NotificationObserverToken?
    private var statusObservation: NSKeyValueObservation?
    private let errorBox = VideoErrorBox()

    /// The key used to associate the `CVMetalTexture` wrapper's lifetime
    /// with the `MTLTexture` itself backing ``texture`` (same pattern as `MLTextureConverter`).
    private static let cvTextureAssociationKey = UnsafeRawPointer(
        UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    )

    // MARK: - Initialization

    /// Loads a video file from the given path.
    ///
    /// - Parameters:
    ///   - path: The file system path to the video file.
    ///   - device: The Metal device used to create the texture cache.
    /// - Throws: ``VideoPlayerError/fileNotFound(_:)`` if the file does not exist.
    public init(path: String, device: MTLDevice) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw VideoPlayerError.fileNotFound(path)
        }

        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)

        // ビデオ出力を BGRA フォーマットで構成
        // （`[String: Any]` ではなく `[String: any Sendable]`: AVFoundation の
        // pixelBufferAttributes は Sendable 制約付きで、`Any` のままだと strict
        // concurrency 下で「'Any' は Sendable に適合しない」と警告される）
        let outputSettings: [String: any Sendable] = [
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
        let metadata = Self.loadAssetMetadataSync(url: url)
        let assetDuration = metadata.duration
        if let naturalSize = metadata.naturalSize {
            self.width = Float(naturalSize.width)
            self.height = Float(naturalSize.height)
        }

        let durationSeconds = CMTimeGetSeconds(assetDuration)
        self.duration = durationSeconds.isNaN ? 0 : durationSeconds

        // 破損ファイル・非対応コーデックはビデオトラックが取れない。
        // この時点で lastError に立てておく（AVPlayerItem.status の .failed は
        // 再生を試みるまで確定しないことがあるため、ここが最初の検出点）
        if !metadata.hasVideoTrack {
            errorBox.store(VideoPlayerError.playbackFailed(
                "no playable video track (corrupt file or unsupported codec?): \(path)"
            ))
        }

        // CVMetalTextureCache を作成
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.textureCache = cache

        // ループ用の再生終了通知を登録
        self.notificationObserver = NotificationObserverToken(
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handlePlaybackEnd()
                }
            }
        )

        // 破損ファイル・非対応コーデック等の失敗を観測する（従来は duration 0・
        // フレーム無しの silent failure だった）。KVO は任意スレッドで届き得る
        // ため、Sendable なエラーボックス経由で公開する
        let errors = errorBox
        self.statusObservation = playerItem.observe(\.status, options: [.new]) { item, _ in
            guard item.status == .failed else { return }
            errors.store(
                item.error ?? VideoPlayerError.playbackFailed("AVPlayerItem.status == .failed")
            )
        }
    }

    deinit {
        // 通知オブザーバの解除は ``NotificationObserverToken`` の deinit が行う
        // （`deinit` は nonisolated なので、@MainActor 隔離された非 Sendable な
        // プロパティをここから触ることはできない）。
        statusObservation?.invalidate()
    }

    /// A helper that synchronously extracts whether a video track exists, plus the
    /// duration and natural size, for the asset at `url`. Waits on the macOS 13+
    /// async API via a `DispatchSemaphore`, preserving the synchronous init's
    /// compatibility while avoiding deprecated-API warnings.
    ///
    /// Takes a `URL` rather than the caller's `AVURLAsset` on purpose: `AVURLAsset`'s
    /// `Sendable` conformance differs between SDK generations (the Xcode 15.4 SDK, our
    /// minimum, still treats it as non-`Sendable`), so capturing the caller's instance
    /// in the detached task would warn there. Loading is read-only and the asset built
    /// here never escapes the task, so re-opening the same local file is equivalent —
    /// and it also keeps the non-`Sendable` `AVAssetTrack` out of the result.
    nonisolated private static func loadAssetMetadataSync(
        url: URL
    ) -> (hasVideoTrack: Bool, duration: CMTime, naturalSize: CGSize?) {
        /// A box for passing load results across, protected by a lock so a
        /// task writing after the timeout does not cause a data race.
        final class MetadataBox: @unchecked Sendable {
            private let lock = NSLock()
            private var hasVideoTrack = false
            private var duration: CMTime = .zero
            private var size: CGSize?

            func set(hasVideoTrack: Bool, duration: CMTime, size: CGSize?) {
                lock.lock()
                self.hasVideoTrack = hasVideoTrack
                self.duration = duration
                self.size = size
                lock.unlock()
            }

            func get() -> (Bool, CMTime, CGSize?) {
                lock.lock()
                defer { lock.unlock() }
                return (hasVideoTrack, duration, size)
            }
        }

        let box = MetadataBox()
        let semaphore = DispatchSemaphore(value: 0)

        Task.detached {
            let asset = AVURLAsset(url: url)
            let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
            var size: CGSize?
            if let track = tracks.first {
                size = try? await track.load(.naturalSize)
            }
            let duration = (try? await asset.load(.duration)) ?? .zero
            box.set(hasVideoTrack: tracks.first != nil, duration: duration, size: size)
            semaphore.signal()
        }

        // ネットワークマウント上のパス等でメタデータ読込が返らない場合に
        // メインスレッドが永久にハングしないようタイムアウトを設ける
        if semaphore.wait(timeout: .now() + 10) == .timedOut {
            metaphorAlert("VideoPlayer: asset metadata load timed out (>10s) — continuing with defaults")
        }
        let (hasVideoTrack, duration, size) = box.get()
        return (hasVideoTrack, duration, size)
    }

    // MARK: - Playback Control

    /// Starts video playback.
    public func play() {
        playback.player.rate = _rate
        isPlaying = true
    }

    /// Pauses video playback. The current position is preserved.
    public func pause() {
        playback.player.pause()
        isPlaying = false
    }

    /// Stops video playback and rewinds to the beginning.
    public func stop() {
        playback.player.pause()
        isPlaying = false
        position = 0
    }

    /// Enables looping playback and starts playback.
    public func loop() {
        isLooping = true
        play()
    }

    // MARK: - Frame Update

    /// Updates the video frame based on the current playback position.
    ///
    /// Call this every frame at the top of your `draw()` method. When a new
    /// frame is available, the `texture` property is updated.
    public func update() {
        // isPlaying では判定しない: 一時停止中のシークでも新フレームが届き、
        // 表示テクスチャへ反映されるべきため（hasNewPixelBuffer だけで足りる）
        let currentTime = playback.player.currentTime()
        guard playback.videoOutput.hasNewPixelBuffer(forItemTime: currentTime) else { return }

        guard let pixelBuffer = playback.videoOutput.copyPixelBuffer(
            forItemTime: currentTime, itemTimeForDisplay: nil
        ) else { return }

        guard let cache = textureCache else { return }

        let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
        let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)

        // 使い終わったキャッシュエントリの内部リソースを回収する。CoreVideo の
        // ドキュメント上、テクスチャキャッシュは定期的な flush を必要とする。
        // 参照が残っている使用中のテクスチャには影響しない。
        CVMetalTextureCacheFlush(cache, 0)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, pixelBuffer, nil,
            .bgra8Unorm, bufferWidth, bufferHeight, 0, &cvTexture
        )

        guard status == kCVReturnSuccess, let cvTex = cvTexture,
              let baseTexture = CVMetalTextureGetTexture(cvTex),
              let mtlTexture = baseTexture.makeTextureView(pixelFormat: baseTexture.pixelFormat)
        else { return }

        // CoreVideo の契約上、MTLTexture はラッパー（cvTex）が生存している間のみ
        // 有効。旧フレームの MTLTexture は in-flight コマンドバッファやユーザ
        // コードから生存し得るため、ラッパーをテクスチャに関連付けて同じ寿命で
        // 生かす（プロパティで 1 世代だけ保持する方式では、描画中のテクスチャの
        // 裏でバッファが再利用され別フレームに上書きされ得る）。ただしラッパーは
        // 内部で baseTexture を retain しているため、baseTexture へ直接関連付けると
        // 循環参照（baseTexture ⇄ cvTex）になり両者とも永遠に解放されない。
        // 同じストレージを指す texture view を作り、view 側へ関連付けることで
        // 参照を一方向（view → cvTex → baseTexture）に保つ
        // （MLTextureConverter と同じパターン）。
        objc_setAssociatedObject(
            mtlTexture, Self.cvTextureAssociationKey, cvTex, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        self.texture = mtlTexture
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
