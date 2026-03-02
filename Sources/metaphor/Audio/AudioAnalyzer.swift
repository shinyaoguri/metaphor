import AVFoundation
import Accelerate
import Foundation

// MARK: - Thread-safe Sample Buffer

/// Transfer audio samples from the audio thread to the main thread.
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

/// Perform FFT analysis and beat detection from microphone or line input.
///
/// Capture audio samples on the audio thread, run FFT analysis, and expose
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

    // MARK: - Public Properties

    /// RMS volume level (0.0 to 1.0).
    public private(set) var volume: Float = 0

    /// Normalized FFT spectrum (0.0 to 1.0).
    public private(set) var spectrum: [Float] = []

    /// Raw waveform data.
    public private(set) var waveform: [Float] = []

    /// Beat detection flag (reset on each call to `update()`).
    public private(set) var isBeat: Bool = false

    /// EMA smoothing coefficient for the spectrum (0.0 = no smoothing, 0.99 = very smooth).
    public var smoothing: Float = 0.8

    /// Beat detection sensitivity (higher values make detection less sensitive).
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
    private var magnitudes: [Float]
    private var fluxHistory: [Float] = []
    private let fluxHistorySize = 43  // ~0.7 seconds at 60 fps

    // MARK: - Initialization

    /// Create an audio analyzer.
    /// - Parameter fftSize: FFT size (must be a power of two, defaults to 1024).
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
        self.magnitudes = [Float](repeating: 0, count: fftSize / 2)
        self.spectrum = [Float](repeating: 0, count: fftSize / 2)
        self.waveform = [Float](repeating: 0, count: fftSize)

        // Pre-compute Hann window
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        // vDSP DFT setup
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

    /// Start audio capture.
    /// - Throws: An error if the audio engine fails to start.
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

    /// Stop audio capture.
    public func stop() {
        guard isRunning else { return }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRunning = false
    }

    /// Update analysis data each frame (call at the beginning of `draw()`).
    ///
    /// Process samples received from the audio thread through FFT and update
    /// `volume`, `spectrum`, `waveform`, and `isBeat`.
    public func update() {
        guard let samples = sampleBuffer.take() ?? injectedSamples else {
            isBeat = false
            return
        }
        injectedSamples = nil
        processSamples(samples)
    }

    /// Inject samples from an external source (used by SoundFile).
    /// - Parameter samples: Audio sample array to inject.
    public func injectSamples(_ samples: [Float]) {
        injectedSamples = samples
    }

    private var injectedSamples: [Float]?

    private func processSamples(_ samples: [Float]) {
        // Store waveform (in-place copy to avoid array buffer reallocation)
        let copyCount = min(samples.count, waveform.count)
        for i in 0..<copyCount {
            waveform[i] = samples[i]
        }
        for i in copyCount..<waveform.count {
            waveform[i] = 0
        }

        // Compute RMS volume
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        volume = min(rms * 4.0, 1.0)

        // FFT
        performFFT(samples)

        // Beat detection
        detectBeat()
    }

    /// Return the energy of a frequency band.
    /// - Parameter index: Band index (0 = bass, 1 = mid, 2 = treble).
    /// - Returns: Band energy (0.0 to 1.0).
    public func band(_ index: Int) -> Float {
        guard !spectrum.isEmpty else { return 0 }

        let bins = halfFFTSize

        let start: Int
        let end: Int

        switch index {
        case 0:
            start = 0
            end = bins / 8           // Bass (~0-250 Hz)
        case 1:
            start = bins / 8
            end = bins / 2           // Mid (~250-2 kHz)
        case 2:
            start = bins / 2
            end = bins               // Treble (~2 kHz+)
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

    /// Return the energy of an arbitrary frequency range.
    /// - Parameters:
    ///   - lowFreq: Lower bound frequency in Hz.
    ///   - highFreq: Upper bound frequency in Hz.
    /// - Returns: Energy level (0.0 to 1.0).
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

        // Apply window function
        vDSP_vmul(samples, 1, window, 1, &realIn, 1, vDSP_Length(fftSize))
        // Imaginary part is zero
        vDSP.fill(&imagIn, with: 0)

        // Execute DFT
        vDSP_DFT_Execute(setup, realIn, imagIn, &realOut, &imagOut)

        // Compute magnitudes (reuse pre-allocated buffer)
        for i in 0..<halfFFTSize {
            let re = realOut[i]
            let im = imagOut[i]
            magnitudes[i] = sqrt(re * re + im * im) / Float(fftSize)
        }

        // Normalize (scale maximum to 1.0)
        var maxMag: Float = 0
        vDSP_maxv(magnitudes, 1, &maxMag, vDSP_Length(halfFFTSize))
        if maxMag > 0.001 {
            var scale = 1.0 / maxMag
            vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(halfFFTSize))
        }

        // EMA smoothing
        let alpha = 1.0 - smoothing
        for i in 0..<halfFFTSize {
            smoothedSpectrum[i] = smoothedSpectrum[i] * smoothing + magnitudes[i] * alpha
        }

        // Copy to spectrum in-place (avoid CoW deferred copy)
        for i in 0..<halfFFTSize {
            spectrum[i] = smoothedSpectrum[i]
        }
    }

    // MARK: - Private: Beat Detection (Spectral Flux)

    private func detectBeat() {
        // Spectral flux: sum of positive differences between current and previous spectrum
        var flux: Float = 0
        let lowBins = min(halfFFTSize / 4, spectrum.count)
        for i in 0..<lowBins {
            let diff = spectrum[i] - previousSpectrum[i]
            if diff > 0 { flux += diff }
        }

        // Store previous spectrum (in-place copy)
        for i in 0..<min(spectrum.count, previousSpectrum.count) {
            previousSpectrum[i] = spectrum[i]
        }

        // Compare against average flux history
        fluxHistory.append(flux)
        if fluxHistory.count > fluxHistorySize {
            fluxHistory.removeFirst()
        }

        let avgFlux = fluxHistory.reduce(0, +) / Float(max(1, fluxHistory.count))
        isBeat = flux > avgFlux * beatThreshold && volume > 0.05
    }
}
