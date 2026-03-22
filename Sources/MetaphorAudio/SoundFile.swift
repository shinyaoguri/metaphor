import AVFoundation
import Foundation
import os

// MARK: - オーディオエンジンホルダー

/// アクター境界を越えて安全にクリーンアップするために AVAudioEngine のライフサイクルを管理します。
///
/// AVAudioEngine と AVAudioPlayerNode の stop 操作はスレッドセーフです。
/// このホルダーが nonisolated(unsafe) を必要とせずに deinit でクリーンアップを処理します。
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

// MARK: - SoundFile 用スレッドセーフサンプルバッファ

private final class SoundSampleBuffer: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: [Float]?.none)

    func store(_ samples: [Float]) {
        state.withLock { $0 = samples }
    }

    func take() -> [Float]? {
        state.withLock { s in let v = s; s = nil; return v }
    }
}

// MARK: - SoundFile

/// オーディオファイル（MP3、WAV、AAC など）を再生し、スペクトル解析と統合します。
///
/// AVAudioEngine と AVAudioPlayerNode を使用してオーディオファイルを再生し、
/// AudioAnalyzer に接続してリアルタイムスペクトル解析を行います。
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

    // MARK: - オーディオエンジン

    private let audioEngine: AudioEngineHolder
    private let file: AVAudioFile
    private let audioFormat: AVAudioFormat

    // MARK: - 再生状態

    /// ファイルが現在再生中かどうかを示します。
    public private(set) var isPlaying: Bool = false

    /// ループ再生の有効・無効を制御します。
    public var isLooping: Bool = false

    /// ファイルの総再生時間（秒）を返します。
    public let duration: Double

    /// 再生音量を制御します（0.0〜1.0）。
    public var volume: Float {
        get { audioEngine.playerNode.volume }
        set { audioEngine.playerNode.volume = max(0, min(1, newValue)) }
    }

    /// 再生速度を制御します（0.25〜4.0）。
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

    // MARK: - 解析統合

    /// ファイル再生のスペクトル解析用内部 AudioAnalyzer。
    private var _analyzer: AudioAnalyzer?
    private let sampleBuffer = SoundSampleBuffer()

    /// スペクトルデータを返します（解析有効時に利用可能）。
    public var spectrum: [Float] { _analyzer?.spectrum ?? [] }

    /// RMS 音量レベルを返します（解析有効時に利用可能）。
    public var analysisVolume: Float { _analyzer?.volume ?? 0 }

    /// ビート検出フラグを返します（解析有効時に利用可能）。
    public var isBeat: Bool { _analyzer?.isBeat ?? false }

    // MARK: - 初期化

    /// 指定パスからオーディオファイルを読み込みます。
    /// - Parameter path: オーディオファイルのファイルシステムパス。
    /// - Throws: ファイルが存在しない場合に `SoundFileError.fileNotFound` をスローします。
    public init(path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw SoundFileError.fileNotFound(path)
        }

        self.file = try AVAudioFile(forReading: url)
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

    /// 再生を開始します。
    public func play() {
        let engine = audioEngine.engine
        if !engine.isRunning {
            do {
                engine.prepare()
                try engine.start()
            } catch {
                debugWarning("Audio engine start failed: \(error)")
                return
            }
        }

        scheduleFile()
        audioEngine.varispeedNode.rate = _rate
        audioEngine.playerNode.play()
        isPlaying = true
    }

    /// 再生を一時停止します。
    public func pause() {
        audioEngine.playerNode.pause()
        isPlaying = false
    }

    /// 再生を停止し、先頭に戻します。
    public func stop() {
        audioEngine.playerNode.stop()
        isPlaying = false
    }

    /// ループを有効にして再生を開始します。
    public func loop() {
        isLooping = true
        play()
    }

    /// 現在の再生位置（秒）を取得または設定します。
    public var position: Double {
        get {
            guard let nodeTime = audioEngine.playerNode.lastRenderTime,
                  let playerTime = audioEngine.playerNode.playerTime(forNodeTime: nodeTime) else {
                return 0
            }
            return Double(playerTime.sampleTime) / playerTime.sampleRate
        }
        set {
            let wasPlaying = isPlaying
            audioEngine.playerNode.stop()

            let samplePosition = AVAudioFramePosition(newValue * audioFormat.sampleRate)
            let remainingFrames = AVAudioFrameCount(file.length - samplePosition)
            guard remainingFrames > 0 else { return }

            audioEngine.playerNode.scheduleSegment(
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
                audioEngine.playerNode.play()
                isPlaying = true
            }
        }
    }

    // MARK: - 解析

    /// オーディオ出力のスペクトル解析を有効にします。
    /// - Parameter fftSize: FFT サイズ（デフォルトは1024）。
    public func enableAnalysis(fftSize: Int = 1024) {
        guard _analyzer == nil else { return }
        _analyzer = AudioAnalyzer(fftSize: fftSize)

        let capturedBuffer = sampleBuffer
        let capturedFFTSize = fftSize

        // メインミキサー出力にタップをインストール
        let mixerFormat = audioEngine.engine.mainMixerNode.outputFormat(forBus: 0)
        audioEngine.engine.mainMixerNode.installTap(
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

    /// 解析データを更新します（`draw()` の先頭で呼び出してください）。
    public func update() {
        guard let analyzer = _analyzer else { return }
        if let samples = sampleBuffer.take() {
            analyzer.injectSamples(samples)
        }
        analyzer.update()
    }

    /// 周波数帯域のエネルギーを返します（AudioAnalyzer 経由）。
    /// - Parameter index: 帯域インデックス（0 = 低音、1 = 中音、2 = 高音）。
    /// - Returns: 帯域エネルギー（0.0〜1.0）。
    public func band(_ index: Int) -> Float {
        _analyzer?.band(index) ?? 0
    }

    // MARK: - プライベート

    private func scheduleFile() {
        audioEngine.playerNode.scheduleFile(
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
            audioEngine.playerNode.stop()
            scheduleFile()
            audioEngine.playerNode.play()
        } else {
            isPlaying = false
        }
    }
}

// MARK: - エラー

/// SoundFile 操作中に発生するエラーを表します。
public enum SoundFileError: Error, LocalizedError {
    /// 指定パスにオーディオファイルが見つからないことを示します。
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Audio file not found: \(path)"
        }
    }
}
