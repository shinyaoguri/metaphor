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

    @Test("Injecting fewer samples than fftSize does not read out of bounds")
    @MainActor
    func injectShortSamples() {
        let analyzer = AudioAnalyzer()  // fftSize = 1024
        // fftSize より短い配列を注入しても配列外読み取りでクラッシュしない。
        analyzer.injectSamples([0.1, -0.2, 0.3, -0.4, 0.5])
        analyzer.update()
        // 正規化後も内部バッファ長は不変。
        #expect(analyzer.spectrum.count == 512)
        #expect(analyzer.waveform.count == 1024)
    }

    @Test("Injecting more samples than fftSize is truncated safely")
    @MainActor
    func injectLongSamples() {
        let analyzer = AudioAnalyzer()  // fftSize = 1024
        analyzer.injectSamples([Float](repeating: 0.25, count: 4096))
        analyzer.update()
        #expect(analyzer.spectrum.count == 512)
        #expect(analyzer.waveform.count == 1024)
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

    @Test("Smoothing is clamped to [0, 0.99]")
    @MainActor
    func smoothingClamped() {
        let analyzer = AudioAnalyzer()
        // 1 以上は spectrum が更新されなくなる（EMA が新値を無視する）
        analyzer.smoothing = 1.5
        #expect(analyzer.smoothing == 0.99)
        // 負値は発散・振動の原因になる
        analyzer.smoothing = -0.5
        #expect(analyzer.smoothing == 0)
    }

    @Test("AudioAnalyzerError has descriptions")
    @MainActor
    func errorDescriptions() {
        #expect(AudioAnalyzerError.noInputDevice.errorDescription?.isEmpty == false)
        #expect(AudioAnalyzerError.microphonePermissionDenied.errorDescription?.isEmpty == false)
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

    @Test("bandEnergy works with injected samples when sampleRate is provided")
    func bandEnergyWithInjectedSampleRate() {
        let sampleRate = 44100.0
        let analyzer = AudioAnalyzer(fftSize: 1024, sampleRate: sampleRate)

        // 440 Hz のサイン波を注入
        var samples = [Float](repeating: 0, count: 1024)
        for i in 0..<1024 {
            samples[i] = sin(Float(i) * 2 * Float.pi * 440.0 / Float(sampleRate)) * 0.5
        }
        analyzer.injectSamples(samples)
        analyzer.update()

        // 修正前は engine 前提のため injectSamples 経由では常に 0 だった
        #expect(analyzer.bandEnergy(lowFreq: 300, highFreq: 600) > 0)
    }

    @Test("bandEnergy returns 0 with injected samples when sampleRate is unknown")
    func bandEnergyWithoutSampleRate() {
        let analyzer = AudioAnalyzer(fftSize: 1024)
        var samples = [Float](repeating: 0, count: 1024)
        for i in 0..<1024 {
            samples[i] = sin(Float(i) * 2 * Float.pi / 64.0) * 0.5
        }
        analyzer.injectSamples(samples)
        analyzer.update()
        #expect(analyzer.bandEnergy(lowFreq: 300, highFreq: 600) == 0)
    }
}

// MARK: - AudioSampleTransferBuffer

@Suite("AudioSampleTransferBuffer")
struct AudioSampleTransferBufferTests {

    @Test("write and take round-trip")
    func roundTrip() {
        let buffer = AudioSampleTransferBuffer(capacity: 4)
        var out = [Float](repeating: -1, count: 4)

        let input: [Float] = [0.1, 0.2, 0.3, 0.4]
        input.withUnsafeBufferPointer { buf in
            buffer.write(buf.baseAddress!, count: buf.count)
        }
        #expect(buffer.take(into: &out))
        #expect(out == input)
        // 2 回目は未読データなし
        #expect(!buffer.take(into: &out))
    }

    @Test("short write zero-fills the remainder")
    func shortWriteZeroFills() {
        let buffer = AudioSampleTransferBuffer(capacity: 4)
        var out = [Float](repeating: -1, count: 4)

        let input: [Float] = [0.5, 0.6]
        input.withUnsafeBufferPointer { buf in
            buffer.write(buf.baseAddress!, count: buf.count)
        }
        #expect(buffer.take(into: &out))
        #expect(out == [0.5, 0.6, 0, 0])
    }

    @Test("oversized write is truncated to capacity")
    func oversizedWriteTruncated() {
        let buffer = AudioSampleTransferBuffer(capacity: 2)
        var out = [Float](repeating: -1, count: 2)

        let input: [Float] = [1, 2, 3, 4]
        input.withUnsafeBufferPointer { buf in
            buffer.write(buf.baseAddress!, count: buf.count)
        }
        #expect(buffer.take(into: &out))
        #expect(out == [1, 2])
    }
}
