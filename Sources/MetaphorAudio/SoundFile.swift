import AVFoundation
import Foundation
import os

// MARK: - Audio Engine Holder

/// Manage AVAudioEngine lifecycle for safe cleanup across actor boundaries.
///
/// AVAudioEngine and AVAudioPlayerNode are thread-safe for stop operations.
/// This holder handles cleanup in deinit without requiring nonisolated(unsafe).
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

// MARK: - Thread-safe Sample Buffer for SoundFile

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

/// Play audio files (MP3, WAV, AAC, etc.) with integrated spectrum analysis.
///
/// Use AVAudioEngine and AVAudioPlayerNode to play audio files, and connect
/// to an AudioAnalyzer for real-time spectrum analysis.
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

    private let audioEngine: AudioEngineHolder
    private let file: AVAudioFile
    private let audioFormat: AVAudioFormat

    // MARK: - Playback State

    /// Indicate whether the file is currently playing.
    public private(set) var isPlaying: Bool = false

    /// Enable or disable loop playback.
    public var isLooping: Bool = false

    /// Return the total duration of the file in seconds.
    public let duration: Double

    /// Control the playback volume (0.0 to 1.0).
    public var volume: Float {
        get { audioEngine.playerNode.volume }
        set { audioEngine.playerNode.volume = max(0, min(1, newValue)) }
    }

    /// Control the playback rate (0.25 to 4.0).
    public var rate: Float {
        get { _rate }
        set {
            _rate = max(0.25, min(4.0, newValue))
            if isPlaying {
                // Rate changes are applied during playback via the varispeed node
                audioEngine.varispeedNode.rate = _rate
            }
        }
    }
    private var _rate: Float = 1.0

    // MARK: - Analysis Integration

    /// Internal AudioAnalyzer for spectrum analysis of file playback.
    private var _analyzer: AudioAnalyzer?
    private let sampleBuffer = SoundSampleBuffer()

    /// Return the spectrum data (available when analysis is enabled).
    public var spectrum: [Float] { _analyzer?.spectrum ?? [] }

    /// Return the RMS volume level (available when analysis is enabled).
    public var analysisVolume: Float { _analyzer?.volume ?? 0 }

    /// Return the beat detection flag (available when analysis is enabled).
    public var isBeat: Bool { _analyzer?.isBeat ?? false }

    // MARK: - Initialization

    /// Load an audio file from the given path.
    /// - Parameter path: File system path to the audio file.
    /// - Throws: `SoundFileError.fileNotFound` if the file does not exist.
    public init(path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw SoundFileError.fileNotFound(path)
        }

        self.file = try AVAudioFile(forReading: url)
        self.audioFormat = file.processingFormat
        self.duration = Double(file.length) / audioFormat.sampleRate

        self.audioEngine = AudioEngineHolder()

        // Connect nodes: playerNode -> varispeed -> mainMixer -> output
        let engine = audioEngine.engine
        let playerNode = audioEngine.playerNode
        let varispeedNode = audioEngine.varispeedNode
        engine.attach(playerNode)
        engine.attach(varispeedNode)
        engine.connect(playerNode, to: varispeedNode, format: audioFormat)
        engine.connect(varispeedNode, to: engine.mainMixerNode, format: audioFormat)
    }

    // MARK: - Playback Control

    /// Start playback.
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

    /// Pause playback.
    public func pause() {
        audioEngine.playerNode.pause()
        isPlaying = false
    }

    /// Stop playback and reset to the beginning.
    public func stop() {
        audioEngine.playerNode.stop()
        isPlaying = false
    }

    /// Enable looping and start playback.
    public func loop() {
        isLooping = true
        play()
    }

    /// Access or set the current playback position in seconds.
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

    // MARK: - Analysis

    /// Enable spectrum analysis on the audio output.
    /// - Parameter fftSize: FFT size (defaults to 1024).
    public func enableAnalysis(fftSize: Int = 1024) {
        guard _analyzer == nil else { return }
        _analyzer = AudioAnalyzer(fftSize: fftSize)

        let capturedBuffer = sampleBuffer
        let capturedFFTSize = fftSize

        // Install a tap on the main mixer output
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

    /// Update analysis data (call at the beginning of `draw()`).
    public func update() {
        guard let analyzer = _analyzer else { return }
        if let samples = sampleBuffer.take() {
            analyzer.injectSamples(samples)
        }
        analyzer.update()
    }

    /// Return the energy of a frequency band (via AudioAnalyzer).
    /// - Parameter index: Band index (0 = bass, 1 = mid, 2 = treble).
    /// - Returns: Band energy (0.0 to 1.0).
    public func band(_ index: Int) -> Float {
        _analyzer?.band(index) ?? 0
    }

    // MARK: - Private

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

// MARK: - Errors

/// Represent errors that occur during SoundFile operations.
public enum SoundFileError: Error, LocalizedError {
    /// Indicate that the audio file was not found at the given path.
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Audio file not found: \(path)"
        }
    }
}
