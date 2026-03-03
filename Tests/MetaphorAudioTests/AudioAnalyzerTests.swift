import Testing
import Foundation
@testable import MetaphorAudio

// MARK: - AudioAnalyzer

@Suite("AudioAnalyzer")
struct AudioAnalyzerTests {

    @Test("Default properties")
    @MainActor
    func defaultProperties() {
        let analyzer = AudioAnalyzer()
        #expect(analyzer.volume == 0)
        #expect(analyzer.spectrum.count == 512)  // fftSize/2 = 1024/2
        #expect(analyzer.waveform.count == 1024)
        #expect(analyzer.isBeat == false)
        #expect(analyzer.smoothing == 0.8)
        #expect(analyzer.beatThreshold == 1.5)
    }

    @Test("Custom FFT size")
    @MainActor
    func customFFTSize() {
        let analyzer = AudioAnalyzer(fftSize: 2048)
        #expect(analyzer.spectrum.count == 1024)
        #expect(analyzer.waveform.count == 2048)
    }

    @Test("Update without samples returns defaults")
    @MainActor
    func updateWithoutSamples() {
        let analyzer = AudioAnalyzer()
        analyzer.update()
        #expect(analyzer.volume == 0)
        #expect(analyzer.isBeat == false)
    }

    @Test("Band returns 0 for empty spectrum")
    @MainActor
    func bandEmpty() {
        let analyzer = AudioAnalyzer()
        // spectrum is initialized with zeros
        #expect(analyzer.band(0) == 0)
        #expect(analyzer.band(1) == 0)
        #expect(analyzer.band(2) == 0)
    }

    @Test("Band returns 0 for out of range index")
    @MainActor
    func bandOutOfRange() {
        let analyzer = AudioAnalyzer()
        #expect(analyzer.band(-1) == 0)
        #expect(analyzer.band(3) == 0)
        #expect(analyzer.band(100) == 0)
    }

    @Test("bandEnergy returns 0 when not running")
    @MainActor
    func bandEnergyNotRunning() {
        let analyzer = AudioAnalyzer()
        #expect(analyzer.bandEnergy(lowFreq: 20, highFreq: 200) == 0)
    }

    @Test("Smoothing property is settable")
    @MainActor
    func smoothingSetting() {
        let analyzer = AudioAnalyzer()
        analyzer.smoothing = 0.95
        #expect(analyzer.smoothing == 0.95)
    }

    @Test("Beat threshold is settable")
    @MainActor
    func beatThresholdSetting() {
        let analyzer = AudioAnalyzer()
        analyzer.beatThreshold = 2.0
        #expect(analyzer.beatThreshold == 2.0)
    }
}

// MARK: - SoundFile

@Suite("SoundFile")
@MainActor
struct SoundFileTests {

    @Test("SoundFileError for non-existent file")
    func fileNotFound() {
        #expect(throws: SoundFileError.self) {
            _ = try SoundFile(path: "/nonexistent/audio.mp3")
        }
    }

    @Test("SoundFileError has description")
    func errorDescription() {
        let error = SoundFileError.fileNotFound("/test/path.mp3")
        #expect(error.errorDescription?.contains("Audio file not found") == true)
    }
}

// MARK: - AudioAnalyzer injectSamples

@Suite("AudioAnalyzer injectSamples")
@MainActor
struct AudioAnalyzerInjectTests {

    @Test("injectSamples feeds data to update")
    func injectSamples() {
        let analyzer = AudioAnalyzer(fftSize: 256)

        // Generate a simple sine wave
        var samples = [Float](repeating: 0, count: 256)
        for i in 0..<256 {
            samples[i] = sin(Float(i) * 2 * Float.pi / 256.0) * 0.5
        }

        analyzer.injectSamples(samples)
        analyzer.update()

        // After update, volume should be non-zero
        #expect(analyzer.volume > 0)
        // Waveform should be populated
        #expect(analyzer.waveform.count == 256)
        // Spectrum should be populated
        #expect(analyzer.spectrum.count == 128)
    }

    @Test("injectSamples without update has no effect")
    func injectWithoutUpdate() {
        let analyzer = AudioAnalyzer(fftSize: 256)

        var samples = [Float](repeating: 0, count: 256)
        for i in 0..<256 {
            samples[i] = sin(Float(i) * 2 * Float.pi / 256.0) * 0.5
        }

        analyzer.injectSamples(samples)
        // Don't call update
        #expect(analyzer.volume == 0)
    }
}
