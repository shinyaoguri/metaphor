import MetaphorCore
import MetaphorAudio

// MARK: - Audio Bridge

extension Sketch {
    /// Create an audio input analyzer for real-time FFT and beat detection.
    ///
    /// - Parameter fftSize: The FFT window size (must be a power of two).
    /// - Returns: A new ``AudioAnalyzer`` instance.
    public func createAudioInput(fftSize: Int = 1024) -> AudioAnalyzer {
        AudioAnalyzer(fftSize: fftSize)
    }

    /// Load an audio file for playback and analysis.
    ///
    /// - Parameter path: The file path to the audio file.
    /// - Returns: A new ``SoundFile`` instance.
    public func loadSound(_ path: String) throws -> SoundFile {
        try SoundFile(path: path)
    }
}
