import AVFoundation
import Foundation

/// オーディオファイル（MP3/WAV/AAC等）の再生とスペクトル解析統合
///
/// AVAudioEngine + AVAudioPlayerNode を使用してオーディオファイルを再生し、
/// AudioAnalyzer と接続してリアルタイムスペクトル解析を行う。
///
/// ```swift
/// var sound: SoundFile!
/// func setup() {
///     sound = try! loadSound("music.mp3")
///     sound.play()
/// }
/// func draw() {
///     sound.update()
///     let vol = sound.volume
///     let spectrum = sound.spectrum
/// }
/// ```
@MainActor
public final class SoundFile {

    // MARK: - Audio Engine

    private let engine: AVAudioEngine
    private let playerNode: AVAudioPlayerNode
    private let file: AVAudioFile
    private let audioFormat: AVAudioFormat

    // MARK: - Playback State

    /// 再生中かどうか
    public private(set) var isPlaying: Bool = false

    /// ループ再生が有効かどうか
    public var isLooping: Bool = false

    /// ファイルの全長（秒）
    public let duration: Double

    /// ボリューム（0.0〜1.0）
    public var volume: Float {
        get { playerNode.volume }
        set { playerNode.volume = max(0, min(1, newValue)) }
    }

    /// 再生レート（0.5〜2.0）
    public var rate: Float {
        get { _rate }
        set {
            _rate = max(0.25, min(4.0, newValue))
            if isPlaying {
                // レート変更は再生中に反映される（varispeed node経由）
                varispeedNode.rate = _rate
            }
        }
    }
    private var _rate: Float = 1.0
    private let varispeedNode: AVAudioUnitVarispeed

    // MARK: - Analysis Integration

    /// 内蔵の AudioAnalyzer（ファイル再生のスペクトル解析用）
    private var _analyzer: AudioAnalyzer?
    private let sampleBuffer = SoundSampleBuffer()

    /// スペクトルデータ（AudioAnalyzer接続時）
    public var spectrum: [Float] { _analyzer?.spectrum ?? [] }

    /// RMS ボリュームレベル（AudioAnalyzer接続時）
    public var analysisVolume: Float { _analyzer?.volume ?? 0 }

    /// ビート検出フラグ（AudioAnalyzer接続時）
    public var isBeat: Bool { _analyzer?.isBeat ?? false }

    // MARK: - Initialization

    /// オーディオファイルを読み込む
    /// - Parameter path: ファイルパス
    public init(path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw SoundFileError.fileNotFound(path)
        }

        self.file = try AVAudioFile(forReading: url)
        self.audioFormat = file.processingFormat
        self.duration = Double(file.length) / audioFormat.sampleRate

        self.engine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()
        self.varispeedNode = AVAudioUnitVarispeed()

        // ノードを接続: playerNode → varispeed → mainMixer → output
        engine.attach(playerNode)
        engine.attach(varispeedNode)
        engine.connect(playerNode, to: varispeedNode, format: audioFormat)
        engine.connect(varispeedNode, to: engine.mainMixerNode, format: audioFormat)
    }

    // MARK: - Playback Control

    /// 再生を開始
    public func play() {
        if !engine.isRunning {
            do {
                engine.prepare()
                try engine.start()
            } catch {
                return
            }
        }

        scheduleFile()
        varispeedNode.rate = _rate
        playerNode.play()
        isPlaying = true
    }

    /// 再生を一時停止
    public func pause() {
        playerNode.pause()
        isPlaying = false
    }

    /// 再生を停止（先頭に戻る）
    public func stop() {
        playerNode.stop()
        isPlaying = false
    }

    /// ループ再生を有効化して再生
    public func loop() {
        isLooping = true
        play()
    }

    /// 現在の再生位置（秒）
    public var position: Double {
        get {
            guard let nodeTime = playerNode.lastRenderTime,
                  let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
                return 0
            }
            return Double(playerTime.sampleTime) / playerTime.sampleRate
        }
        set {
            let wasPlaying = isPlaying
            playerNode.stop()

            let samplePosition = AVAudioFramePosition(newValue * audioFormat.sampleRate)
            let remainingFrames = AVAudioFrameCount(file.length - samplePosition)
            guard remainingFrames > 0 else { return }

            playerNode.scheduleSegment(
                file,
                startingFrame: samplePosition,
                frameCount: remainingFrames,
                at: nil,
                completionCallbackType: .dataPlayedBack
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.handlePlaybackCompletion()
                }
            }

            if wasPlaying {
                playerNode.play()
                isPlaying = true
            }
        }
    }

    // MARK: - Analysis

    /// スペクトル解析を有効化
    /// - Parameter fftSize: FFT サイズ（デフォルト1024）
    public func enableAnalysis(fftSize: Int = 1024) {
        guard _analyzer == nil else { return }
        _analyzer = AudioAnalyzer(fftSize: fftSize)

        let capturedBuffer = sampleBuffer
        let capturedFFTSize = fftSize

        // mainMixer の出力にタップを設置
        let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.mainMixerNode.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(fftSize),
            format: mixerFormat
        ) { audioBuffer, _ in
            guard let channelData = audioBuffer.floatChannelData else { return }
            let frameCount = Int(audioBuffer.frameLength)
            let count = min(frameCount, capturedFFTSize)

            var samples = [Float](repeating: 0, count: capturedFFTSize)
            for i in 0..<count {
                samples[i] = channelData[0][i]
            }
            capturedBuffer.store(samples)
        }
    }

    /// 解析データを更新（draw() の先頭で呼ぶ）
    public func update() {
        guard let analyzer = _analyzer else { return }
        if let samples = sampleBuffer.take() {
            analyzer.injectSamples(samples)
        }
        analyzer.update()
    }

    /// バンドエネルギーを取得（AudioAnalyzer経由）
    public func band(_ index: Int) -> Float {
        _analyzer?.band(index) ?? 0
    }

    // MARK: - Private

    private func scheduleFile() {
        playerNode.scheduleFile(
            file,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.handlePlaybackCompletion()
            }
        }
    }

    private func handlePlaybackCompletion() {
        if isLooping {
            playerNode.stop()
            scheduleFile()
            playerNode.play()
        } else {
            isPlaying = false
        }
    }
}

// MARK: - Errors

public enum SoundFileError: Error, LocalizedError {
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Audio file not found: \(path)"
        }
    }
}

// MARK: - Thread-safe Sample Buffer for SoundFile

private final class SoundSampleBuffer: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var _samples: [Float]?

    func store(_ samples: [Float]) {
        lock.lock()
        _samples = samples
        lock.unlock()
    }

    func take() -> [Float]? {
        lock.lock()
        let s = _samples
        _samples = nil
        lock.unlock()
        return s
    }
}
