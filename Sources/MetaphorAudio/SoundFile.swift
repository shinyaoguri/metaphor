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

    /// 再生ゲインを制御します（0.0〜1.0）。
    public var gain: Float {
        get { audioEngine.playerNode.volume }
        set { audioEngine.playerNode.volume = max(0, min(1, newValue)) }
    }

    /// ``gain`` の旧名。
    @available(*, deprecated, renamed: "gain")
    public var volume: Float {
        get { gain }
        set { gain = newValue }
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

    /// playerNode のキューに未消化のスケジュール（ファイル全体またはセグメント）が
    /// あるかどうか。pause() → play() の再開時に同じファイルを二重スケジュール
    /// しないために追跡する。
    private var hasPendingSchedule: Bool = false

    /// スケジュール世代カウンタ。`AVAudioPlayerNode.stop()` は保留中の completion
    /// handler を「再生完了」と区別できない形で発火させるため、stop()/シークの
    /// たびに世代を進め、completion handler 側で世代一致を確認して stale な
    /// completion（停止直後のループ再開・シークの巻き戻し）を無害化する。
    /// （internal なのはテストから stale completion を模擬するため）
    private(set) var scheduleGeneration: UInt64 = 0

    /// pause() 時点の再生位置キャッシュ。一時停止中は `playerTime(forNodeTime:)`
    /// が nil を返し位置が巻き戻って見えるため、ここで保持した値を返す。
    private var pausedPosition: Double?

    /// 直近の再生操作で発生したエラー（現在は `play()` のエンジン起動失敗）。
    /// `play()` は Processing 風の使い勝手を保つため throws にしない代わりに、
    /// 失敗をこのプロパティで報告する（成功時は nil に戻る）。
    public private(set) var lastError: Error?

    /// 直近のスケジュールが始まったファイル内位置（秒）。
    /// playerNode の sampleTime はスケジュールし直すたびに 0 から数え直されるため、
    /// シーク後も ``position`` が正しいファイル内位置を返すための基準値。
    private var scheduledBaseTime: Double = 0

    // MARK: - 解析統合

    /// ファイル再生のスペクトル解析用内部 AudioAnalyzer。
    private var _analyzer: AudioAnalyzer?
    private var sampleBuffer: AudioSampleTransferBuffer?
    private var tapScratch: [Float] = []

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
    ///
    /// エンジンの起動に失敗した場合はクラッシュせず再生を開始しません。
    /// 失敗の内容は ``lastError`` で確認できます。
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

    /// 再生を一時停止します。
    public func pause() {
        // pause 中は playerTime(forNodeTime:) が nil になり位置が巻き戻って
        // 見えるため、pause 直前の位置をキャッシュしておく
        pausedPosition = position
        audioEngine.playerNode.pause()
        isPlaying = false
    }

    /// 再生を停止し、先頭に戻します。
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

    /// ループを有効にして再生を開始します。
    public func loop() {
        isLooping = true
        play()
    }

    /// 現在の再生位置（秒）を取得または設定します。
    ///
    /// 設定値は `0...duration` にクランプされます。末尾以降へのシークは停止扱いです。
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
                DispatchQueue.main.async {
                    self?.handlePlaybackCompletion(generation: generation)
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

    /// オーディオ出力のスペクトル解析を有効にします。
    /// - Parameter fftSize: FFT サイズ（デフォルトは1024）。
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

    /// 解析データを更新します（`draw()` の先頭で呼び出してください）。
    public func update() {
        guard let analyzer = _analyzer else { return }
        if let sampleBuffer, sampleBuffer.take(into: &tapScratch) {
            analyzer.injectSamples(tapScratch)
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
        scheduleGeneration &+= 1
        let generation = scheduleGeneration
        audioEngine.playerNode.scheduleFile(
            file,
            at: nil,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.handlePlaybackCompletion(generation: generation)
            }
        }
        hasPendingSchedule = true
        scheduledBaseTime = 0
    }

    /// （internal なのはテストから stale completion の配送を模擬するため）
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
