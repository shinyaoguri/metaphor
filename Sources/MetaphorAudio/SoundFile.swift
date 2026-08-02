import AVFoundation
import Foundation
import os

// MARK: - オーディオエンジンホルダー

/// Manages the lifecycle of `AVAudioEngine` for safe cleanup across actor boundaries.
///
/// The stop operations on `AVAudioEngine` and `AVAudioPlayerNode` are thread-safe.
/// This holder handles cleanup in `deinit` without needing `nonisolated(unsafe)`.
private final class AudioEngineHolder: @unchecked Sendable {
    let engine: AVAudioEngine
    let playerNode: AVAudioPlayerNode
    let varispeedNode: AVAudioUnitVarispeed

    init() {
        self.engine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()
        self.varispeedNode = AVAudioUnitVarispeed()
    }

    deinit {
        playerNode.stop()
        engine.stop()
    }
}

// MARK: - SoundFile

/// Plays an audio file (MP3, WAV, AAC, etc.) and integrates spectrum analysis.
///
/// Plays an audio file using `AVAudioEngine` and `AVAudioPlayerNode`, and
/// connects to an `AudioAnalyzer` for real-time spectrum analysis.
///
/// ```swift
/// var sound: SoundFile?
/// func setup() {
///     do {
///         sound = try loadSound("music.mp3")
///         sound?.play()
///     } catch {
///         print("Failed to load sound: \(error)")
///     }
/// }
/// func draw() {
///     guard let sound else { return }
///     sound.update()
///     let vol = sound.gain
///     let spectrum = sound.spectrum
/// }
/// ```
@MainActor
public final class SoundFile {

    // MARK: - オーディオエンジン

    private let audioEngine: AudioEngineHolder
    private let file: AVAudioFile
    private let audioFormat: AVAudioFormat

    // MARK: - 再生状態

    /// Indicates whether the file is currently playing.
    public private(set) var isPlaying: Bool = false

    /// Controls whether looping playback is enabled.
    public var isLooping: Bool = false

    /// Returns the file's total duration (seconds).
    public let duration: Double

    /// Controls the playback gain (0.0-1.0).
    public var gain: Float {
        get { audioEngine.playerNode.volume }
        set { audioEngine.playerNode.volume = max(0, min(1, newValue)) }
    }

    /// Controls the playback rate (0.25-4.0).
    public var rate: Float {
        get { _rate }
        set {
            _rate = max(0.25, min(4.0, newValue))
            if isPlaying {
                // 再生中の速度変更は varispeed ノード経由で適用
                audioEngine.varispeedNode.rate = _rate
            }
        }
    }
    private var _rate: Float = 1.0

    /// Whether the playerNode's queue has an outstanding schedule (the whole
    /// file or a segment). Tracked so that resuming via pause() → play() does
    /// not double-schedule the same file.
    private var hasPendingSchedule: Bool = false

    /// Schedule generation counter. `AVAudioPlayerNode.stop()` fires any
    /// pending completion handler in a way indistinguishable from "playback
    /// finished", so the generation is advanced on every stop()/seek, and the
    /// completion handler checks it matches before acting — neutralizing
    /// stale completions (e.g. a loop restart or seek rewind right after a
    /// stop). (Internal so tests can simulate a stale completion.)
    private(set) var scheduleGeneration: UInt64 = 0

    /// Cached playback position at the moment of pause(). While paused,
    /// `playerTime(forNodeTime:)` returns nil and the position would appear
    /// to rewind, so this cached value is returned instead.
    private var pausedPosition: Double?

    /// The error from the most recent playback operation (currently only an
    /// engine start failure in `play()`). `play()` is not `throws` — to keep
    /// Processing-style ergonomics — and instead reports failures through
    /// this property (reset to nil on success).
    public private(set) var lastError: Error?

    /// The in-file position (seconds) where the most recent schedule began.
    /// The playerNode's `sampleTime` restarts from 0 every time playback is
    /// rescheduled, so this serves as the baseline that lets ``position``
    /// return the correct in-file position even after seeking.
    private var scheduledBaseTime: Double = 0

    // MARK: - 解析統合

    /// The internal `AudioAnalyzer` used for spectrum analysis of file playback.
    private var _analyzer: AudioAnalyzer?
    private var sampleBuffer: AudioSampleTransferBuffer?
    private var tapScratch: [Float] = []

    /// Returns spectrum data (available once analysis is enabled).
    public var spectrum: [Float] { _analyzer?.spectrum ?? [] }

    /// Returns the RMS volume level (available once analysis is enabled).
    public var analysisVolume: Float { _analyzer?.volume ?? 0 }

    /// Returns the beat detection flag (available once analysis is enabled).
    public var isBeat: Bool { _analyzer?.isBeat ?? false }

    // MARK: - 初期化

    /// Loads an audio file from the given path.
    /// - Parameter path: The file system path to the audio file.
    /// - Throws: ``SoundFileError/fileNotFound(_:)`` if the file does not exist, or
    ///   ``SoundFileError/loadFailed(path:detail:)`` if the file cannot be decoded
    ///   (unsupported codec, corrupted data, insufficient permissions).
    public init(path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw SoundFileError.fileNotFound(path)
        }

        do {
            self.file = try AVAudioFile(forReading: url)
        } catch {
            // Do not let the raw AVFoundation NSError escape: this module's error
            // contract is SoundFileError only.
            throw SoundFileError.loadFailed(path: path, detail: error.localizedDescription)
        }
        self.audioFormat = file.processingFormat
        self.duration = Double(file.length) / audioFormat.sampleRate

        self.audioEngine = AudioEngineHolder()

        // ノードを接続: playerNode -> varispeed -> mainMixer -> output
        let engine = audioEngine.engine
        let playerNode = audioEngine.playerNode
        let varispeedNode = audioEngine.varispeedNode
        engine.attach(playerNode)
        engine.attach(varispeedNode)
        engine.connect(playerNode, to: varispeedNode, format: audioFormat)
        engine.connect(varispeedNode, to: engine.mainMixerNode, format: audioFormat)
    }

    // MARK: - 再生コントロール

    /// Starts playback.
    ///
    /// If the engine fails to start, playback does not begin and the app
    /// does not crash. The failure can be inspected via ``lastError``.
    public func play() {
        let engine = audioEngine.engine
        if !engine.isRunning {
            do {
                engine.prepare()
                try engine.start()
            } catch {
                lastError = error
                debugWarning("Audio engine start failed: \(error)")
                return
            }
        }
        lastError = nil

        // pause() からの再開やシーク直後はキューに残っているスケジュールを
        // そのまま再生する。無条件に scheduleFile() すると同じファイルが
        // 二重にキューイングされ、現在の再生終了後にもう一度頭から流れる。
        if !hasPendingSchedule {
            scheduleFile()
        }
        audioEngine.varispeedNode.rate = _rate
        audioEngine.playerNode.play()
        pausedPosition = nil
        isPlaying = true
    }

    /// Pauses playback.
    public func pause() {
        // pause 中は playerTime(forNodeTime:) が nil になり位置が巻き戻って
        // 見えるため、pause 直前の位置をキャッシュしておく
        pausedPosition = position
        audioEngine.playerNode.pause()
        isPlaying = false
    }

    /// Stops playback and returns to the beginning.
    public func stop() {
        // stop() は保留中の completion handler を発火させる。世代を進めて
        // stale completion（ループ再開など）を無害化する
        scheduleGeneration &+= 1
        audioEngine.playerNode.stop()
        isPlaying = false
        // stop() は playerNode のキューを破棄する
        hasPendingSchedule = false
        scheduledBaseTime = 0
        pausedPosition = nil
    }

    /// Enables looping and starts playback.
    public func loop() {
        isLooping = true
        play()
    }

    /// Gets or sets the current playback position (seconds).
    ///
    /// Values set are clamped to `0...duration`. Seeking at or past the end is treated as a stop.
    public var position: Double {
        get {
            // 一時停止中は playerTime(forNodeTime:) が nil になるため、
            // pause() 時点でキャッシュした位置を返す
            if let pausedPosition { return pausedPosition }
            guard let nodeTime = audioEngine.playerNode.lastRenderTime,
                  let playerTime = audioEngine.playerNode.playerTime(forNodeTime: nodeTime) else {
                return scheduledBaseTime
            }
            // sampleTime はスケジュール開始からの経過。シーク位置を加算して
            // ファイル内の絶対位置を返す。
            return scheduledBaseTime + Double(playerTime.sampleTime) / playerTime.sampleRate
        }
        set {
            let wasPlaying = isPlaying
            // stop() はキューを破棄する（hasPendingSchedule / 基準値もリセット）
            stop()

            // 範囲外の値で AVAudioFrameCount（UInt32）の初期化がトラップしない
            // よう、ファイル範囲にクランプする
            let clamped = max(0, min(newValue, duration))
            let samplePosition = AVAudioFramePosition(clamped * audioFormat.sampleRate)
            let remainingFrames64 = file.length - samplePosition
            guard remainingFrames64 > 0 else { return }

            scheduleGeneration &+= 1
            let generation = scheduleGeneration
            audioEngine.playerNode.scheduleSegment(
                file,
                startingFrame: samplePosition,
                frameCount: AVAudioFrameCount(remainingFrames64),
                at: nil,
                completionCallbackType: .dataPlayedBack
            ) { [weak self] _ in
                // `self` を一度 let に束ねてから内側の @Sendable クロージャへ渡す
                // （`[weak self]` が導入する暗黙の var を直接キャプチャすると
                // strict concurrency が「並行実行されるコードで捕捉された var を
                // 参照している」と警告する）。SoundFile は @MainActor なので
                // 暗黙に Sendable であり、Optional ごと安全に渡せる。
                let sound = self
                DispatchQueue.main.async {
                    sound?.handlePlaybackCompletion(generation: generation)
                }
            }
            hasPendingSchedule = true
            scheduledBaseTime = clamped

            if wasPlaying {
                audioEngine.playerNode.play()
                isPlaying = true
            }
        }
    }

    // MARK: - 解析

    /// Enables spectrum analysis of the audio output.
    /// - Parameter fftSize: The FFT size (defaults to 1024).
    public func enableAnalysis(fftSize: Int = 1024) {
        guard _analyzer == nil else { return }
        let mixerFormat = audioEngine.engine.mainMixerNode.outputFormat(forBus: 0)
        // sampleRate を渡すことで injectSamples 経由でも bandEnergy() が機能する
        _analyzer = AudioAnalyzer(fftSize: fftSize, sampleRate: mixerFormat.sampleRate)

        let buffer = AudioSampleTransferBuffer(capacity: fftSize)
        sampleBuffer = buffer
        tapScratch = [Float](repeating: 0, count: fftSize)

        // メインミキサー出力にタップをインストール
        audioEngine.engine.mainMixerNode.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(fftSize),
            format: mixerFormat
        ) { audioBuffer, _ in
            guard let channelData = audioBuffer.floatChannelData else { return }
            // オーディオ経路ではアロケーションしない（固定長バッファへコピー）
            buffer.write(channelData[0], count: Int(audioBuffer.frameLength))
        }
    }

    /// Disables spectrum analysis and releases the analyzer.
    ///
    /// Removes the tap installed on the main mixer by ``enableAnalysis(fftSize:)``.
    /// After this call ``spectrum``, ``analysisVolume``, ``isBeat`` and ``band(_:)``
    /// report their neutral values again, and ``update()`` becomes a no-op.
    /// Calling it while analysis is not enabled does nothing.
    public func disableAnalysis() {
        guard _analyzer != nil else { return }
        audioEngine.engine.mainMixerNode.removeTap(onBus: 0)
        _analyzer = nil
        sampleBuffer = nil
        tapScratch = []
    }

    /// Updates analysis data (call this at the top of `draw()`).
    public func update() {
        guard let analyzer = _analyzer else { return }
        if let sampleBuffer, sampleBuffer.take(into: &tapScratch) {
            analyzer.injectSamples(tapScratch)
        }
        analyzer.update()
    }

    /// Returns the energy of a frequency band (via `AudioAnalyzer`).
    /// - Parameter index: The band index (0 = low, 1 = mid, 2 = high).
    /// - Returns: The band energy (0.0-1.0).
    public func band(_ index: Int) -> Float {
        _analyzer?.band(index) ?? 0
    }

    // MARK: - プライベート

    private func scheduleFile() {
        scheduleGeneration &+= 1
        let generation = scheduleGeneration
        audioEngine.playerNode.scheduleFile(
            file,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            // scheduleSegment 側と同じ理由で let に束ねてから渡す。
            let sound = self
            DispatchQueue.main.async {
                sound?.handlePlaybackCompletion(generation: generation)
            }
        }
        hasPendingSchedule = true
        scheduledBaseTime = 0
    }

    /// (Internal so tests can simulate delivery of a stale completion.)
    func handlePlaybackCompletion(generation: UInt64) {
        // stop()/シークは世代を進めるため、それ以前にスケジュールされた
        // completion はここで棄却される（stop 後のループ再開・シークの
        // 巻き戻しを防ぐ）
        guard generation == scheduleGeneration else { return }
        hasPendingSchedule = false
        if isLooping {
            audioEngine.playerNode.stop()
            scheduleFile()
            audioEngine.playerNode.play()
        } else {
            isPlaying = false
        }
    }
}

// MARK: - エラー

/// Represents errors that can occur during `SoundFile` operations.
///
/// Throwing `SoundFile` APIs only ever throw this type: failures coming from
/// AVFoundation are wrapped into ``loadFailed(path:detail:)`` rather than being
/// re-thrown as raw `NSError`.
public enum SoundFileError: Error, LocalizedError, Sendable {
    /// Indicates that no audio file was found at the given path.
    case fileNotFound(String)
    /// Indicates that the audio file exists but could not be opened or decoded.
    case loadFailed(path: String, detail: String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Audio file not found: \(path)"
        case .loadFailed(let path, let detail):
            return "Failed to load audio file '\(path)': \(detail)"
        }
    }
}
