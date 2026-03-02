import AVFoundation
import Accelerate
import Foundation

// MARK: - Thread-safe Sample Buffer

/// オーディオスレッド → メインスレッド間のサンプル受け渡し用
private final class AudioSampleBuffer: Sendable {
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

// MARK: - AudioAnalyzer

/// マイク/ライン入力からの FFT 解析 + ビート検出
///
/// オーディオスレッドでキャプチャしたサンプルを FFT 解析し、
/// メインスレッドからスペクトル・波形・ビート情報にアクセスできる。
///
/// ```swift
/// let audio = createAudioInput()
/// try audio.start()
///
/// func draw() {
///     audio.update()
///     let vol = audio.volume
///     let bass = audio.band(0)
///     if audio.isBeat { /* flash! */ }
/// }
/// ```
@MainActor
public final class AudioAnalyzer {

    // MARK: - Public Properties

    /// RMS ボリューム（0.0〜1.0）
    public private(set) var volume: Float = 0

    /// FFT スペクトル（正規化済み、0.0〜1.0）
    public private(set) var spectrum: [Float] = []

    /// 生波形データ
    public private(set) var waveform: [Float] = []

    /// ビート検出フラグ（update() 毎にリセット）
    public private(set) var isBeat: Bool = false

    /// スペクトルの EMA スムージング係数（0.0=スムージングなし, 0.99=非常に滑らか）
    public var smoothing: Float = 0.8

    /// ビート検出の感度（大きいほど鈍感）
    public var beatThreshold: Float = 1.5

    // MARK: - Audio Engine

    private var engine: AVAudioEngine?
    private let fftSize: Int
    private let halfFFTSize: Int
    private var isRunning = false

    // MARK: - vDSP FFT

    private nonisolated(unsafe) var fftSetup: vDSP_DFT_Setup?
    private var window: [Float]
    private var realIn: [Float]
    private var imagIn: [Float]
    private var realOut: [Float]
    private var imagOut: [Float]

    // MARK: - Thread-safe Transfer

    private let sampleBuffer = AudioSampleBuffer()

    // MARK: - Internal State

    private var smoothedSpectrum: [Float]
    private var previousSpectrum: [Float]
    private var fluxHistory: [Float] = []
    private let fluxHistorySize = 43  // ~0.7秒分（60fps）

    // MARK: - Initialization

    /// AudioAnalyzer を作成
    /// - Parameter fftSize: FFT サイズ（2の冪乗、デフォルト1024）
    public init(fftSize: Int = 1024) {
        self.fftSize = fftSize
        self.halfFFTSize = fftSize / 2

        self.window = [Float](repeating: 0, count: fftSize)
        self.realIn = [Float](repeating: 0, count: fftSize)
        self.imagIn = [Float](repeating: 0, count: fftSize)
        self.realOut = [Float](repeating: 0, count: fftSize)
        self.imagOut = [Float](repeating: 0, count: fftSize)
        self.smoothedSpectrum = [Float](repeating: 0, count: fftSize / 2)
        self.previousSpectrum = [Float](repeating: 0, count: fftSize / 2)
        self.spectrum = [Float](repeating: 0, count: fftSize / 2)
        self.waveform = [Float](repeating: 0, count: fftSize)

        // Hann 窓を事前計算
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        // vDSP DFT セットアップ
        self.fftSetup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            .FORWARD
        )
    }

    deinit {
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }

    // MARK: - Public API

    /// オーディオキャプチャを開始
    public func start() throws {
        guard !isRunning else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let capturedFFTSize = fftSize
        let buffer = sampleBuffer

        inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: format) {
            audioBuffer, _ in
            guard let channelData = audioBuffer.floatChannelData else { return }

            let frameCount = Int(audioBuffer.frameLength)
            let count = min(frameCount, capturedFFTSize)

            var samples = [Float](repeating: 0, count: capturedFFTSize)
            for i in 0..<count {
                samples[i] = channelData[0][i]
            }

            buffer.store(samples)
        }

        engine.prepare()
        try engine.start()

        self.engine = engine
        self.isRunning = true
    }

    /// オーディオキャプチャを停止
    public func stop() {
        guard isRunning else { return }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRunning = false
    }

    /// 毎フレーム呼ぶ更新メソッド（draw() の先頭で呼ぶ）
    ///
    /// オーディオスレッドから受け取ったサンプルを FFT 解析し、
    /// volume / spectrum / waveform / isBeat を更新する。
    public func update() {
        guard let samples = sampleBuffer.take() ?? injectedSamples else {
            isBeat = false
            return
        }
        injectedSamples = nil
        processSamples(samples)
    }

    /// 外部からサンプルを注入（SoundFile から使用）
    public func injectSamples(_ samples: [Float]) {
        injectedSamples = samples
    }

    private var injectedSamples: [Float]?

    private func processSamples(_ samples: [Float]) {
        // 波形を保存
        waveform = samples

        // RMS ボリューム計算
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        volume = min(rms * 4.0, 1.0)

        // FFT
        performFFT(samples)

        // ビート検出
        detectBeat()
    }

    /// バンドエネルギーを取得（0=低音, 1=中音, 2=高音）
    /// - Parameter index: バンドインデックス（0, 1, 2）
    /// - Returns: バンドエネルギー（0.0〜1.0）
    public func band(_ index: Int) -> Float {
        guard !spectrum.isEmpty else { return 0 }

        let bins = halfFFTSize

        let start: Int
        let end: Int

        switch index {
        case 0:
            start = 0
            end = bins / 8           // 低音 (~0-250Hz)
        case 1:
            start = bins / 8
            end = bins / 2           // 中音 (~250-2kHz)
        case 2:
            start = bins / 2
            end = bins               // 高音 (~2kHz+)
        default:
            return 0
        }

        guard start < end, end <= spectrum.count else { return 0 }

        var sum: Float = 0
        for i in start..<end {
            sum += spectrum[i]
        }
        return sum / Float(end - start)
    }

    /// 任意の周波数帯域のエネルギーを取得
    /// - Parameters:
    ///   - lowFreq: 下限周波数（Hz）
    ///   - highFreq: 上限周波数（Hz）
    /// - Returns: エネルギー（0.0〜1.0）
    public func bandEnergy(lowFreq: Float, highFreq: Float) -> Float {
        guard !spectrum.isEmpty, let engine else { return 0 }

        let sampleRate = Float(engine.inputNode.outputFormat(forBus: 0).sampleRate)
        let binWidth = sampleRate / Float(fftSize)

        let lowBin = max(0, Int(lowFreq / binWidth))
        let highBin = min(halfFFTSize - 1, Int(highFreq / binWidth))

        guard lowBin <= highBin else { return 0 }

        var sum: Float = 0
        for i in lowBin...highBin {
            sum += spectrum[i]
        }
        return sum / Float(highBin - lowBin + 1)
    }

    // MARK: - Private: FFT

    private func performFFT(_ samples: [Float]) {
        guard let setup = fftSetup else { return }

        // 窓関数適用
        vDSP_vmul(samples, 1, window, 1, &realIn, 1, vDSP_Length(fftSize))
        // 虚部はゼロ
        vDSP.fill(&imagIn, with: 0)

        // DFT 実行
        vDSP_DFT_Execute(setup, realIn, imagIn, &realOut, &imagOut)

        // マグニチュード計算
        var magnitudes = [Float](repeating: 0, count: halfFFTSize)
        for i in 0..<halfFFTSize {
            let re = realOut[i]
            let im = imagOut[i]
            magnitudes[i] = sqrt(re * re + im * im) / Float(fftSize)
        }

        // 正規化（最大値を1.0に）
        var maxMag: Float = 0
        vDSP_maxv(magnitudes, 1, &maxMag, vDSP_Length(halfFFTSize))
        if maxMag > 0.001 {
            var scale = 1.0 / maxMag
            vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(halfFFTSize))
        }

        // EMA スムージング
        let alpha = 1.0 - smoothing
        for i in 0..<halfFFTSize {
            smoothedSpectrum[i] = smoothedSpectrum[i] * smoothing + magnitudes[i] * alpha
        }

        spectrum = smoothedSpectrum
    }

    // MARK: - Private: Beat Detection (Spectral Flux)

    private func detectBeat() {
        // スペクトルフラックス: 現在のスペクトルと前フレームの差分の正の部分の合計
        var flux: Float = 0
        let lowBins = min(halfFFTSize / 4, spectrum.count)
        for i in 0..<lowBins {
            let diff = spectrum[i] - previousSpectrum[i]
            if diff > 0 { flux += diff }
        }

        // 前フレームのスペクトルを保存
        previousSpectrum = spectrum

        // フラックス履歴の平均と比較
        fluxHistory.append(flux)
        if fluxHistory.count > fluxHistorySize {
            fluxHistory.removeFirst()
        }

        let avgFlux = fluxHistory.reduce(0, +) / Float(max(1, fluxHistory.count))
        isBeat = flux > avgFlux * beatThreshold && volume > 0.05
    }
}
