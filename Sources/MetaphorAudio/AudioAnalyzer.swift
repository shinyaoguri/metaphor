import AVFoundation
import Accelerate
import Foundation
import os

// MARK: - スレッドセーフなサンプルバッファ

/// Transfers samples from the audio thread to the main thread.
///
/// Copies into a fixed-length buffer allocated at init time, to avoid
/// allocations on the audio path (tap callback) and freeing the old
/// array while holding the lock.
final class AudioSampleTransferBuffer: Sendable {
    private struct State {
        var samples: [Float]
        var hasData: Bool = false
    }
    private let state: OSAllocatedUnfairLock<State>

    init(capacity: Int) {
        state = OSAllocatedUnfairLock(
            initialState: State(samples: [Float](repeating: 0, count: capacity))
        )
    }

    /// Call from the audio thread. Copies the first `count` elements of
    /// `data` into the fixed-length buffer (zero-fills any shortfall).
    /// Allocates nothing.
    ///
    /// - Note: `withLockUnchecked` is used because capturing a pointer and
    ///   inout fails the Sendable check. The closure runs synchronously
    ///   inside the lock and never lets the value escape, so this is safe.
    func write(_ data: UnsafePointer<Float>, count: Int) {
        state.withLockUnchecked { s in
            let capacity = s.samples.count
            let n = min(count, capacity)
            s.samples.withUnsafeMutableBufferPointer { buf in
                guard let base = buf.baseAddress else { return }
                base.update(from: data, count: n)
                if n < capacity {
                    base.advanced(by: n).update(repeating: 0, count: capacity - n)
                }
            }
            s.hasData = true
        }
    }

    /// Call from the main thread. If unread data is available, copies it
    /// into `out` and returns true.
    func take(into out: inout [Float]) -> Bool {
        state.withLockUnchecked { s in
            guard s.hasData else { return false }
            let n = min(s.samples.count, out.count)
            out.withUnsafeMutableBufferPointer { ob in
                s.samples.withUnsafeBufferPointer { ib in
                    guard let outBase = ob.baseAddress, let inBase = ib.baseAddress else { return }
                    outBase.update(from: inBase, count: n)
                    if n < ob.count {
                        outBase.advanced(by: n).update(repeating: 0, count: ob.count - n)
                    }
                }
            }
            s.hasData = false
            return true
        }
    }
}

// MARK: - FFT セットアップホルダー

/// Wrapper that safely manages the lifecycle of `vDSP_DFT_Setup` across actor boundaries.
private final class FFTSetupHolder: @unchecked Sendable {
    let setup: vDSP_DFT_Setup?
    init(size: Int) {
        setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(size), .FORWARD)
    }
    deinit {
        if let setup { vDSP_DFT_DestroySetup(setup) }
    }
}

// MARK: - AudioAnalyzer

/// Performs FFT analysis and beat detection on microphone or line input.
///
/// Captures samples on the audio thread, runs FFT analysis, and exposes
/// spectrum, waveform, and beat information on the main thread.
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

    // MARK: - パブリックプロパティ

    /// RMS volume level (0.0-1.0).
    public private(set) var volume: Float = 0

    /// Normalized FFT spectrum (0.0-1.0).
    public private(set) var spectrum: [Float] = []

    /// Raw waveform data.
    public private(set) var waveform: [Float] = []

    /// Beat detection flag (reset on every `update()` call).
    public private(set) var isBeat: Bool = false

    /// EMA smoothing factor for the spectrum (0.0 = no smoothing, 0.99 = very smooth).
    ///
    /// Out-of-range values are clamped to [0, 0.99] (values of 1 or greater
    /// stop `spectrum` from updating, and negative values diverge and oscillate).
    public var smoothing: Float = 0.8 {
        didSet { smoothing = min(max(smoothing, 0), 0.99) }
    }

    /// Beat detection sensitivity (higher values make detection less sensitive).
    public var beatThreshold: Float = 1.5

    /// The sample rate of the audio being analyzed (Hz).
    ///
    /// No need to set this when using ``start()`` — it is obtained
    /// automatically from the input device. When analyzing external samples
    /// via ``injectSamples(_:)``, it is used for the frequency-to-bin
    /// conversion in ``bandEnergy(lowFreq:highFreq:)``.
    public var sampleRate: Double?

    /// Called (on the main thread) when the audio engine's configuration
    /// changes, e.g. an input device disconnects or the sample rate changes.
    /// Analysis silently stops after a disconnect, so this callback lets you
    /// detect that and reconfigure by calling `stop()` then `start()`.
    public var onConfigurationChange: (() -> Void)?

    // MARK: - オーディオエンジン

    private var engine: AVAudioEngine?
    private let fftSize: Int
    private let halfFFTSize: Int
    private var isRunning = false
    private var configurationObserver: NSObjectProtocol?

    // MARK: - vDSP FFT

    private let fftHolder: FFTSetupHolder
    private var window: [Float]
    private var realIn: [Float]
    private var imagIn: [Float]
    private var realOut: [Float]
    private var imagOut: [Float]

    // MARK: - スレッドセーフ転送

    private let sampleBuffer: AudioSampleTransferBuffer
    private var tapSamples: [Float]

    // MARK: - 内部状態

    private var smoothedSpectrum: [Float]
    private var previousSpectrum: [Float]
    private var magnitudes: [Float]
    private var fluxHistory: [Float] = []
    private let fluxHistorySize = 43  // 60fps で約0.7秒

    // MARK: - 初期化

    /// Creates an audio analyzer.
    /// - Parameters:
    ///   - fftSize: The FFT size (must be a power of 2; defaults to 1024).
    ///   - sampleRate: The sample rate (Hz) when analyzing via ``injectSamples(_:)``.
    ///     Not needed when using ``start()`` (obtained automatically from the input device).
    public init(fftSize: Int = 1024, sampleRate: Double? = nil) {
        self.fftSize = fftSize
        self.halfFFTSize = fftSize / 2
        self.sampleRate = sampleRate
        self.sampleBuffer = AudioSampleTransferBuffer(capacity: fftSize)
        self.tapSamples = [Float](repeating: 0, count: fftSize)

        self.window = [Float](repeating: 0, count: fftSize)
        self.realIn = [Float](repeating: 0, count: fftSize)
        self.imagIn = [Float](repeating: 0, count: fftSize)
        self.realOut = [Float](repeating: 0, count: fftSize)
        self.imagOut = [Float](repeating: 0, count: fftSize)
        self.smoothedSpectrum = [Float](repeating: 0, count: fftSize / 2)
        self.previousSpectrum = [Float](repeating: 0, count: fftSize / 2)
        self.magnitudes = [Float](repeating: 0, count: fftSize / 2)
        self.spectrum = [Float](repeating: 0, count: fftSize / 2)
        self.waveform = [Float](repeating: 0, count: fftSize)

        // ハン窓を事前計算
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        // vDSP DFT セットアップ（ホルダーが安全な deinit のためにライフサイクルを管理）
        self.fftHolder = FFTSetupHolder(size: fftSize)
    }

    // MARK: - パブリック API

    /// Starts audio capture.
    /// - Throws: ``AudioAnalyzerError/microphonePermissionDenied`` if microphone
    ///   permission has been denied, ``AudioAnalyzerError/noInputDevice`` if no
    ///   input device is available, or another error if the audio engine
    ///   otherwise fails to start.
    public func start() throws {
        guard !isRunning else { return }

        // マイク権限が明示的に拒否されていると無音が流れ続けるだけで原因が
        // 分からないため、専用エラーで報告する（.notDetermined の場合は
        // エンジン起動時にシステムが権限ダイアログを出すのでそのまま進む）
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            throw AudioAnalyzerError.microphonePermissionDenied
        default:
            break
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // 入力デバイス不在時は sampleRate 0 のフォーマットが返り、そのまま
        // installTap すると ObjC 例外（Swift の catch では捕捉不可）で
        // プロセスごとクラッシュするため、事前に検証する
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioAnalyzerError.noInputDevice
        }

        let buffer = sampleBuffer
        inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: format) {
            audioBuffer, _ in
            guard let channelData = audioBuffer.floatChannelData else { return }
            // オーディオ経路ではアロケーションしない（固定長バッファへコピー）
            buffer.write(channelData[0], count: Int(audioBuffer.frameLength))
        }

        engine.prepare()
        try engine.start()

        // デバイス切断・サンプルレート変更などの構成変化を監視する
        // （切断後は解析が静かに止まるため、少なくとも観測可能にする）
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleConfigurationChange()
            }
        }

        self.engine = engine
        self.isRunning = true
    }

    /// Stops audio capture.
    public func stop() {
        guard isRunning else { return }
        if let observer = configurationObserver {
            NotificationCenter.default.removeObserver(observer)
            configurationObserver = nil
        }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRunning = false
    }

    deinit {
        if let observer = configurationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Updates analysis data once per frame (call this at the top of `draw()`).
    ///
    /// Processes samples received from the audio thread through the FFT and
    /// updates `volume`, `spectrum`, `waveform`, and `isBeat`.
    public func update() {
        if sampleBuffer.take(into: &tapSamples) {
            injectedSamples = nil
            processSamples(tapSamples)
        } else if let samples = injectedSamples {
            injectedSamples = nil
            processSamples(samples)
        } else {
            isBeat = false
        }
    }

    /// Injects samples from an external source (used by SoundFile).
    /// - Parameter samples: The array of audio samples to inject.
    public func injectSamples(_ samples: [Float]) {
        injectedSamples = samples
    }

    private var injectedSamples: [Float]?

    private func processSamples(_ rawSamples: [Float]) {
        // FFT 経路（performFFT 内の vDSP_vmul）は常に fftSize 要素を読むため、
        // 入力長を fftSize に正規化する。tap 経路は常に fftSize 長だが、
        // injectSamples（SoundFile など外部ソース）は任意長を渡しうるため、
        // ここで不足は0埋め・超過は切り詰めし、配列外メモリ読み取りを防ぐ。
        let samples: [Float]
        if rawSamples.count == fftSize {
            samples = rawSamples
        } else {
            var normalized = [Float](repeating: 0, count: fftSize)
            let n = min(rawSamples.count, fftSize)
            for i in 0..<n { normalized[i] = rawSamples[i] }
            samples = normalized
        }

        // 波形を保存（配列バッファの再確保を避けるためインプレースコピー）
        let copyCount = min(samples.count, waveform.count)
        for i in 0..<copyCount {
            waveform[i] = samples[i]
        }
        for i in copyCount..<waveform.count {
            waveform[i] = 0
        }

        // RMS 音量を計算
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        volume = min(rms * 4.0, 1.0)

        // FFT
        performFFT(samples)

        // ビート検出
        detectBeat()
    }

    /// Returns the energy of a frequency band.
    /// - Parameter index: The band index (0 = low, 1 = mid, 2 = high).
    /// - Returns: The band energy (0.0-1.0).
    public func band(_ index: Int) -> Float {
        guard !spectrum.isEmpty else { return 0 }

        let bins = halfFFTSize

        let start: Int
        let end: Int

        switch index {
        case 0:
            start = 0
            end = bins / 8           // 低音（〜0-250 Hz）
        case 1:
            start = bins / 8
            end = bins / 2           // 中音（〜250-2 kHz）
        case 2:
            start = bins / 2
            end = bins               // 高音（〜2 kHz+）
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

    /// Returns the energy of an arbitrary frequency range.
    /// - Parameters:
    ///   - lowFreq: The lower bound frequency (Hz).
    ///   - highFreq: The upper bound frequency (Hz).
    /// - Returns: The energy level (0.0-1.0).
    public func bandEnergy(lowFreq: Float, highFreq: Float) -> Float {
        guard !spectrum.isEmpty else { return 0 }

        // engine 稼働中は入力デバイスの実サンプルレートを優先し、
        // injectSamples 経由の解析では ``sampleRate`` プロパティを使う
        let engineRate = engine.map { $0.inputNode.outputFormat(forBus: 0).sampleRate }
        guard let rate = engineRate ?? sampleRate, rate > 0 else { return 0 }
        let binWidth = Float(rate) / Float(fftSize)

        let lowBin = max(0, Int(lowFreq / binWidth))
        let highBin = min(halfFFTSize - 1, Int(highFreq / binWidth))

        guard lowBin <= highBin else { return 0 }

        var sum: Float = 0
        for i in lowBin...highBin {
            sum += spectrum[i]
        }
        return sum / Float(highBin - lowBin + 1)
    }

    // MARK: - プライベート: FFT

    private func performFFT(_ samples: [Float]) {
        guard let setup = fftHolder.setup else { return }

        // 窓関数を適用
        vDSP_vmul(samples, 1, window, 1, &realIn, 1, vDSP_Length(fftSize))
        // 虚数部はゼロ
        vDSP.fill(&imagIn, with: 0)

        // DFT を実行
        vDSP_DFT_Execute(setup, realIn, imagIn, &realOut, &imagOut)

        // 振幅を計算（事前確保済みバッファを再利用）
        for i in 0..<halfFFTSize {
            let re = realOut[i]
            let im = imagOut[i]
            magnitudes[i] = sqrt(re * re + im * im) / Float(fftSize)
        }

        // 正規化（最大値を 1.0 にスケーリング）
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

        // スペクトルにインプレースコピー（CoW の遅延コピーを回避）
        for i in 0..<halfFFTSize {
            spectrum[i] = smoothedSpectrum[i]
        }
    }

    // MARK: - プライベート: ビート検出（スペクトラルフラックス）

    private func detectBeat() {
        // スペクトラルフラックス: 現在と前回のスペクトルの正の差分の合計
        var flux: Float = 0
        let lowBins = min(halfFFTSize / 4, spectrum.count)
        for i in 0..<lowBins {
            let diff = spectrum[i] - previousSpectrum[i]
            if diff > 0 { flux += diff }
        }

        // 前回のスペクトルを保存（インプレースコピー）
        for i in 0..<min(spectrum.count, previousSpectrum.count) {
            previousSpectrum[i] = spectrum[i]
        }

        // フラックス履歴の平均と比較
        fluxHistory.append(flux)
        if fluxHistory.count > fluxHistorySize {
            fluxHistory.removeFirst()
        }

        let avgFlux = fluxHistory.reduce(0, +) / Float(max(1, fluxHistory.count))
        isBeat = flux > avgFlux * beatThreshold && volume > 0.05
    }

    // MARK: - プライベート: 構成変化

    private func handleConfigurationChange() {
        debugWarning("Audio engine configuration changed (device disconnected or sample rate changed?)")
        onConfigurationChange?()
    }
}

// MARK: - エラー

/// Represents errors that can occur during `AudioAnalyzer` operations.
public enum AudioAnalyzerError: Error, LocalizedError {
    /// Indicates that no audio input device is available.
    case noInputDevice
    /// Indicates that microphone permission has been denied.
    case microphonePermissionDenied

    public var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No audio input device is available"
        case .microphonePermissionDenied:
            return "Microphone permission has been denied. "
                + "Enable it in System Settings > Privacy & Security > Microphone"
        }
    }
}
