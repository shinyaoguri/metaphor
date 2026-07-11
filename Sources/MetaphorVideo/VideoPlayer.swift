import AVFoundation
import CoreVideo
import Foundation
import Metal
import ObjectiveC.runtime

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
    /// アイテムの読み込み・再生に失敗した（破損ファイル・非対応コーデック等）。
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

/// KVO（任意スレッド）で観測したエラーをメインスレッドの poll 系 API へ渡します。
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

    /// アイテムの読み込み・再生エラー（破損ファイル・非対応コーデック等）。
    ///
    /// AVPlayerItem の失敗は非同期に確定するため、`draw()` 内の ``update()`` と
    /// 同じ要領でこのプロパティを確認してください（失敗時は ``isAvailable`` が
    /// false のまま・フレームが届かない silent failure になっていた）。
    public var lastError: (any Error)? { errorBox.value }

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
    private var statusObservation: NSKeyValueObservation?
    private let errorBox = VideoErrorBox()

    /// ``texture`` を支える CVMetalTexture ラッパーの寿命を MTLTexture 自体に
    /// 関連付けるためのキー（MLTextureConverter と同じパターン）。
    private static let cvTextureAssociationKey = UnsafeRawPointer(
        UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    )

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

        // 破損ファイル・非対応コーデックはビデオトラックが取れない。
        // この時点で lastError に立てておく（AVPlayerItem.status の .failed は
        // 再生を試みるまで確定しないことがあるため、ここが最初の検出点）
        if metadata.track == nil {
            errorBox.store(VideoPlayerError.playbackFailed(
                "no playable video track (corrupt file or unsupported codec?): \(path)"
            ))
        }

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
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        statusObservation?.invalidate()
    }

    /// `AVURLAsset` のトラック・再生時間・サイズを同期的に取り出すヘルパー。
    /// macOS 13+ の async API を `DispatchSemaphore` で待つことで、
    /// 同期 init の互換性を保ちつつ非推奨 API の警告を回避する。
    nonisolated private static func loadAssetMetadataSync(
        _ asset: AVURLAsset
    ) -> (track: AVAssetTrack?, duration: CMTime, naturalSize: CGSize?) {
        /// ロード結果の受け渡し用ボックス（タイムアウト後にタスクが書き込んでも
        /// データ競合にならないようロックで保護する）。
        final class MetadataBox: @unchecked Sendable {
            private let lock = NSLock()
            private var track: AVAssetTrack?
            private var duration: CMTime = .zero
            private var size: CGSize?

            func set(track: AVAssetTrack?, duration: CMTime, size: CGSize?) {
                lock.lock()
                self.track = track
                self.duration = duration
                self.size = size
                lock.unlock()
            }

            func get() -> (AVAssetTrack?, CMTime, CGSize?) {
                lock.lock()
                defer { lock.unlock() }
                return (track, duration, size)
            }
        }

        let box = MetadataBox()
        let semaphore = DispatchSemaphore(value: 0)

        Task.detached {
            let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
            var size: CGSize?
            if let track = tracks.first {
                size = try? await track.load(.naturalSize)
            }
            let duration = (try? await asset.load(.duration)) ?? .zero
            box.set(track: tracks.first, duration: duration, size: size)
            semaphore.signal()
        }

        // ネットワークマウント上のパス等でメタデータ読込が返らない場合に
        // メインスレッドが永久にハングしないようタイムアウトを設ける
        if semaphore.wait(timeout: .now() + 10) == .timedOut {
            print("[metaphor] VideoPlayer: asset metadata load timed out (>10s) — continuing with defaults")
        }
        let (track, duration, size) = box.get()
        return (track, duration, size)
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
