import MetaphorCore
import MetaphorAudio

// MARK: - オーディオブリッジ

extension Sketch {
    /// Creates an audio input analyzer for real-time FFT and beat detection.
    ///
    /// Call `start()` to begin analysis — it does not start on its own.
    ///
    /// - Parameter fftSize: The FFT window size, a power of two. A value that is
    ///   not a power of two logs a warning and falls back to the default (1024).
    /// - Returns: A new ``MetaphorAudio/AudioAnalyzer`` instance.
    public func createAudioInput(fftSize: Int = 1024) -> AudioAnalyzer {
        guard fftSize >= 2, (fftSize & (fftSize - 1)) == 0 else {
            metaphorWarning(
                "createAudioInput: fftSize must be a power of two (got \(fftSize)); using 1024")
            return AudioAnalyzer(fftSize: 1024)
        }
        return AudioAnalyzer(fftSize: fftSize)
    }

    /// Loads an audio file for playback and analysis.
    ///
    /// - Parameter path: The file path of the audio file.
    /// - Returns: A new ``MetaphorAudio/SoundFile`` instance.
    /// - Throws: ``MetaphorAudio/SoundFileError/fileNotFound(_:)`` when the file
    ///   does not exist, or ``MetaphorAudio/SoundFileError/loadFailed(path:detail:)``
    ///   when decoding or loading fails.
    public func loadSound(_ path: String) throws -> SoundFile {
        try SoundFile(path: path)
    }
}
